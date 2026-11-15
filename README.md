# Firebase Cloud Quest

## Project Overview

Firebase Cloud Quest is a Flutter mobile application I developed to practice using Firebase Authentication, Cloud Firestore, Cloud Functions, and generative AI together. The application allows students to sign in, view a daily challenge, complete it to earn points and a badge, and ask an AI Quest Coach questions about the challenge.

I built the project using Firebase emulators so I could test the application and its security rules locally.

## Technologies Used

- Flutter and Dart
- Firebase Authentication
- Cloud Firestore
- Firebase Cloud Functions (Node.js)
- Genkit with Gemini
- Firebase Local Emulator Suite

## Features

### Authentication

Students can create an account, sign in using their email and password, and sign out. Authentication is required before accessing the daily challenge or using the AI Coach.

### Daily Challenge

The application retrieves the daily challenge from the `challenges/today` document in Firestore.

The challenge contains a title and prompt that the student can read after signing in.

### Challenge Completion

Students can complete the daily challenge and receive 10 points and the `first-quest` badge.

The reward is processed by the `completeToday` Cloud Function using a Firestore transaction. Completing the same challenge again does not award additional points.

### AI Quest Coach

I added an AI Quest Coach using Genkit and Gemini. Students can ask questions about the daily challenge, and the AI provides short educational explanations.

The AI Coach can also read the signed-in student's progress using the `readMyQuestState` tool. This tool is read-only and cannot update points or badges.

Questions are limited to 300 characters. The Gemini API key is kept in the Cloud Functions environment rather than in the Flutter application.

## Firestore Data Structure

Daily challenge:

`challenges/today`

Fields:
- `title`
- `prompt`

Student progress:

`users/{uid}/progress/today`

Fields:
- `completed`
- `points`
- `badgeId`
- `completedAt`

## Security

I used Firebase Authentication and Firestore security rules to protect student data.

Only authenticated students can read the daily challenge. Students can read their own progress but cannot access another student's progress.

Direct client writes to challenge and progress documents are denied. Rewards are updated through the trusted Cloud Function instead.

The AI Coach receives the authenticated student's identity from the callable request. It does not accept a student UID from the question text.

## Local Setup

Install Flutter, Node.js, and Firebase CLI.

Install the Cloud Functions dependencies:

```bash
cd functions
npm install
cd ..
```

Configure Firebase for Flutter:

```bash
flutterfire configure
```

Configure the Gemini API key for the local Functions emulator using a private `functions/.secret.local` file. This file must not be committed to Git.

Start the emulators:

```bash
firebase emulators:start --only auth,firestore,functions
```

Create the `challenges/today` document in the Firestore emulator with a `title` and `prompt`.

Run the Flutter application:

```bash
flutter run
```

The Flutter application connects to the local Firebase emulators during development.

## Testing

I tested the application using the Android emulator and Firebase Local Emulator Suite.

The following features worked during testing:

- Creating an account and signing in
- Signing out
- Reading the daily challenge
- Completing a challenge and receiving 10 points
- Receiving the `first-quest` badge
- Preventing duplicate rewards
- Asking the AI Coach a question
- Reading student progress through the AI tool
- Rejecting requests to change points or badges through the AI
- Handling empty questions
- Enforcing the 300-character question limit

### Automated Firestore Security Tests

I also wrote seven automated tests for the Firestore security rules.

To run them from the project root:

```bash
firebase emulators:exec --only firestore "node --test functions/tests/firestore.rules.test.js"
```

Final test results:

```text
tests 7
pass 7
fail 0
```

The tests confirmed that authenticated students can read permitted data, unauthenticated access is denied, students cannot read or modify another student's progress, and direct client writes to protected documents are blocked.

The `PERMISSION_DENIED` messages produced during the negative tests were expected because those tests deliberately attempted unauthorized operations.

## Graduate Reflection

The most important thing I learned from this assignment was how to separate the mobile application's responsibilities from trusted backend operations. Initially, I thought the main challenge would be connecting Flutter to Firebase, but testing the security rules and Cloud Functions helped me understand why sensitive updates should not be handled directly by the client.

I used a Firestore transaction to prevent students from receiving duplicate rewards. I also made the AI Coach's progress tool read-only so it could explain a student's progress without changing it.

One issue I encountered was selecting a working Gemini model and resolving repeated Genkit tool registration warnings. I tested the API separately and adjusted the implementation until the AI Coach worked correctly.

The automated security tests were useful because they confirmed that unauthorized operations were actually rejected, rather than just relying on the application's interface.

## Trust Boundary Explanation

The Flutter application is an untrusted client. It can request information and call backend functions, but it cannot directly award points or badges.

Firebase Authentication identifies the signed-in student. Firestore security rules restrict document access, while Cloud Functions perform trusted reward updates.

The AI Coach is also restricted. Its progress-reading tool uses the authenticated request context and does not expose a write operation.

This separation helps prevent students from changing their own rewards, accessing another student's progress, or using AI prompts to bypass the application's security rules.