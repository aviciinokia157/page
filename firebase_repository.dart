import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseReservationRepository {
  FirebaseReservationRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    FirebaseMessaging? messaging,
  })  : db = firestore ?? FirebaseFirestore.instance,
        firebaseAuth = auth ?? FirebaseAuth.instance,
        firebaseStorage = storage ?? FirebaseStorage.instance,
        firebaseMessaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseFirestore db;
  final FirebaseAuth firebaseAuth;
  final FirebaseStorage firebaseStorage;
  final FirebaseMessaging firebaseMessaging;

  Future<UserCredential> registerWithEmail({required String email, required String password}) {
    return firebaseAuth.createUserWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signInWithEmail({required String email, required String password}) {
    return firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> sendPasswordReset(String email) {
    return firebaseAuth.sendPasswordResetEmail(email: email);
  }

  Future<void> ensureUserProfile({
    required String uid,
    required String fullName,
    required String phone,
    required String email,
    String? photoUrl,
  }) async {
    final userRef = db.collection('users').doc(uid);
    final bootstrapRef = db.collection('settings').doc('bootstrap');

    await db.runTransaction((tx) async {
      final bootstrap = await tx.get(bootstrapRef);
      final firstUser = !bootstrap.exists;
      tx.set(userRef, {
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'photoUrl': photoUrl,
        'role': firstUser ? 'mainAdmin' : 'user',
        'blocked': false,
        'createdAt': FieldValue.serverTimestamp(),
        'reservationCount': 0,
      }, SetOptions(merge: true));
      if (firstUser) {
        tx.set(bootstrapRef, {
          'mainAdminUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamTables() {
    return db.collection('tables').orderBy('number').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamReservationsForAdmin() {
    return db.collection('reservations').orderBy('date').orderBy('timeSlot').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamReservationsForUser(String uid) {
    return db.collection('reservations').where('userId', isEqualTo: uid).orderBy('date').snapshots();
  }

  Future<void> createOrUpdateTable({
    required String tableId,
    required int number,
    required int capacity,
    required double x,
    required double y,
    bool blocked = false,
  }) {
    return db.collection('tables').doc(tableId).set({
      'number': number,
      'capacity': capacity,
      'x': x,
      'y': y,
      'blocked': blocked,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<DocumentReference<Map<String, dynamic>>> createReservation({
    required String userId,
    required String responsibleName,
    required String phone,
    required String email,
    required String tableId,
    required int tableNumber,
    required DateTime date,
    required String timeSlot,
    required int guests,
    required String notes,
  }) async {
    final dateKey = date.year.toString().padLeft(4, '0') + date.month.toString().padLeft(2, '0') + date.day.toString().padLeft(2, '0');
    final lockId = tableId + '_' + dateKey + '_' + timeSlot.replaceAll(':', '');
    final lockRef = db.collection('reservationLocks').doc(lockId);
    final reservationRef = db.collection('reservations').doc();
    final userRef = db.collection('users').doc(userId);

    await db.runTransaction((tx) async {
      final lock = await tx.get(lockRef);
      if (lock.exists) {
        throw StateError('Mesa indisponivel para esta data e horario.');
      }
      tx.set(lockRef, {
        'tableId': tableId,
        'dateKey': dateKey,
        'timeSlot': timeSlot,
        'reservationId': reservationRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(reservationRef, {
        'userId': userId,
        'responsibleName': responsibleName,
        'phone': phone,
        'email': email,
        'tableId': tableId,
        'tableNumber': tableNumber,
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'timeSlot': timeSlot,
        'guests': guests,
        'notes': notes,
        'status': 'confirmed',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(userRef, {'reservationCount': FieldValue.increment(1)});
      tx.set(db.collection('auditLogs').doc(), {
        'userId': userId,
        'action': 'reservation_created',
        'reservationId': reservationRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return reservationRef;
  }

  Future<void> updateReservationStatus({
    required String reservationId,
    required String status,
    required String actorId,
  }) {
    final reservationRef = db.collection('reservations').doc(reservationId);
    final logRef = db.collection('auditLogs').doc();
    return db.runTransaction((tx) async {
      tx.update(reservationRef, {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(logRef, {
        'actorId': actorId,
        'reservationId': reservationId,
        'action': 'status_' + status,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> saveNotificationToken(String uid) async {
    final token = await firebaseMessaging.getToken();
    if (token == null) return;
    await db.collection('users').doc(uid).set({
      'notificationTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  Future<String> uploadProfilePhoto({required String uid, required Uint8List bytes, required String extension}) async {
    final ref = firebaseStorage.ref('users/' + uid + '/profile.' + extension);
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  Future<void> writeSystemBackup({required Uint8List bytes, required String fileName}) async {
    final ref = firebaseStorage.ref('backups/' + fileName);
    await ref.putData(bytes);
  }
}
