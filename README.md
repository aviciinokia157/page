# Reserva de Convidados

Aplicativo Flutter premium para Android, iOS e Web com reservas de mesas, mapa visual, painel administrativo, QR Code, relatorios PDF/Excel e estrutura Firebase.

## Incluso

- Cadastro, login demonstrativo e recuperacao de senha preparada.
- Primeiro usuario como Administrador Principal.
- Dashboard com metricas, graficos e historico.
- Mapa de mesas responsivo com status Livre, Reservada e Bloqueada.
- Criacao, cancelamento e confirmacao de presenca por QR Code.
- Gerenciamento de mesas, usuarios, permissoes e bloqueios.
- Calendario inteligente, pesquisa global e lista de espera.
- Relatorios em PDF e Excel.
- Personalizacao do estabelecimento e modo claro/escuro.
- Regras Firestore, Storage, indices e Firebase Hosting.

## Rodar

```bash
flutter pub get
flutter run -d chrome
```

Android:

```bash
flutter build apk --release
```

iOS:

```bash
flutter build ipa --release
```

## Ativar Firebase real

1. Crie um projeto no Firebase.
2. Ative Authentication com E-mail/Senha, Google e Apple.
3. Ative Cloud Firestore, Storage e Cloud Messaging.
4. Rode `flutterfire configure` ou substitua os valores em `lib/firebase_options.dart`.
5. Publique regras e indices com `firebase deploy --only firestore:rules,firestore:indexes,storage`.

## Bloqueio contra duplicidade

Use transacao Firestore criando `reservationLocks/{tableId}_{yyyyMMdd}_{HHmm}`. A reserva so e confirmada se esse documento ainda nao existir.


## Camada Firebase real

O arquivo `lib/firebase_repository.dart` contem operacoes reais para Auth, Firestore, Storage e Cloud Messaging, incluindo transacao para bloquear reserva duplicada pela chave `reservationLocks/{tableId}_{yyyyMMdd}_{HHmm}`.

A interface principal inicia em modo demonstracao quando as chaves Firebase ainda estao como `SUBSTITUA_...`. Depois de configurar o Firebase, conecte os fluxos da tela ao repositorio conforme a politica de produto desejada.
