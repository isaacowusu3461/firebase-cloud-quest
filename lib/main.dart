
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Connect my app to Firebase.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // I use the local Firebase services for Android testing.
  // This prevents test accounts and rewards from affecting live data.
  if (kDebugMode && defaultTargetPlatform == TargetPlatform.android) {
    const host = '10.0.2.2';

    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  }

  runApp(const CloudQuestApp());
}

class CloudQuestApp extends StatelessWidget {
  const CloudQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Cloud Quest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      // Firebase updates this screen when a student signs in or out.
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData) {
            return const QuestHomeScreen();
          }

          return const AuthScreen();
        },
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  String? errorMessage;

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Please enter your email and password.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // The same form handles registration and sign-in.
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.message ?? 'Authentication failed.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2FA),
      appBar: AppBar(
        title: const Text('Cloud Quest'),
        backgroundColor: const Color(0xFFDCE2FA),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_outlined,
                  size: 72,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 20),
                Text(
                  isLogin ? 'Welcome Back' : 'Create an Account',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isLoading ? null : submit,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isLogin ? 'Sign In' : 'Register'),
                  ),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          setState(() {
                            isLogin = !isLogin;
                            errorMessage = null;
                          });
                        },
                  child: Text(
                    isLogin
                        ? 'Create a new account'
                        : 'Already have an account? Sign in',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuestHomeScreen extends StatefulWidget {
  const QuestHomeScreen({super.key});

  @override
  State<QuestHomeScreen> createState() => _QuestHomeScreenState();
}

class _QuestHomeScreenState extends State<QuestHomeScreen> {
  bool isCompleting = false;
  String? completionMessage;

  // Keep the student's question and the latest coach response on this screen.
  final questionController = TextEditingController();
  bool isAskingCoach = false;
  String? coachAnswer;
  String? coachError;

  @override
  void dispose() {
    questionController.dispose();
    super.dispose();
  }

  Future<void> askQuestCoach() async {
    if (isAskingCoach) return;

    final question = questionController.text.trim();
    if (question.isEmpty || question.length > 300) {
      setState(() {
        coachError = 'Enter a question between 1 and 300 characters.';
        coachAnswer = null;
      });
      return;
    }

    setState(() {
      isAskingCoach = true;
      coachError = null;
      coachAnswer = null;
    });

    try {
      // The question goes to our callable function, not directly to Gemini.
      final result = await FirebaseFunctions.instance
          .httpsCallable('askQuestCoach')
          .call<Map<String, dynamic>>({'question': question});

      final answer = result.data['answer'];
      if (answer is! String || answer.trim().isEmpty) {
        throw const FormatException('Empty response from the coach');
      }

      if (!mounted) return;
      setState(() {
        coachAnswer = answer.trim();
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        coachError = e.message ?? 'The coach could not answer right now.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        coachError = 'The coach is unavailable. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isAskingCoach = false;
        });
      }
    }
  }

  Widget buildCoachCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.smart_toy_outlined, color: Colors.indigo),
                SizedBox(width: 10),
                Text(
                  'AI Quest Coach',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Ask for a hint or an explanation about today\'s quest.'),
            const SizedBox(height: 16),
            TextField(
              controller: questionController,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              enabled: !isAskingCoach,
              decoration: const InputDecoration(
                labelText: 'Your question',
                hintText: 'Why is Firebase Authentication useful?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isAskingCoach ? null : askQuestCoach,
                icon: isAskingCoach
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(isAskingCoach ? 'Asking Coach...' : 'Ask Coach'),
              ),
            ),
            if (coachError != null) ...[
              const SizedBox(height: 12),
              Text(coachError!, style: const TextStyle(color: Colors.red)),
            ],
            if (coachAnswer != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Coach response',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(coachAnswer!),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> completeChallenge() async {
    if (isCompleting) return;

    setState(() {
      isCompleting = true;
      completionMessage = null;
    });

    try {
      // The backend checks the signed-in user and awards the points.
      // I do not write points directly from the Flutter app.
      final callable = FirebaseFunctions.instance.httpsCallable(
        'completeToday',
      );

      final result = await callable.call<Map<String, dynamic>>({
        'challengeId': 'today',
      });

      final data = result.data;
      final alreadyCompleted = data['alreadyCompleted'] == true;
      final points = data['points'];

      if (!mounted) return;

      setState(() {
        completionMessage = alreadyCompleted
            ? 'You already completed this challenge. Your reward is still $points points.'
            : 'Challenge completed! You earned $points points and the First Quest badge.';
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;

      setState(() {
        completionMessage =
            'Could not complete the challenge: ${e.message ?? e.code}';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        completionMessage = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isCompleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // Listen for the daily challenge from Firestore.
    final challengeStream = FirebaseFirestore.instance
        .collection('challenges')
        .doc('today')
        .snapshots();

    // Students can read their own progress but cannot edit rewards.
    final progressStream = user == null
        ? null
        : FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('progress')
            .doc('today')
            .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2FA),
      appBar: AppBar(
        title: const Text('Cloud Quest'),
        backgroundColor: const Color(0xFFDCE2FA),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.cloud_outlined,
                  size: 64,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Daily Cloud Quest',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Signed in as ${user?.email ?? 'Student'}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: challengeStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Could not load the challenge. '
                            'Please check your connection and try again.',
                          ),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (!snapshot.data!.exists) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No daily challenge has been added yet.',
                          ),
                        ),
                      );
                    }

                    final data = snapshot.data!.data() ?? {};
                    final title = data['title'] as String? ?? '';
                    final prompt = data['prompt'] as String? ?? '';

                    if (title.isEmpty || prompt.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'The challenge information is incomplete.',
                          ),
                        ),
                      );
                    }

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "TODAY'S CHALLENGE",
                              style: TextStyle(
                                color: Colors.indigo,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              prompt,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 8),
                            const Text(
                              'Reward: 10 points and First Quest badge',
                            ),
                            const SizedBox(height: 16),

                            // The progress document updates after the function
                            // successfully saves the student's reward.
                            StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>
                            >(
                              stream: progressStream,
                              builder: (context, progressSnapshot) {
                                if (progressSnapshot.hasError) {
                                  return const Text(
                                    'Could not load your progress.',
                                  );
                                }

                                if (!progressSnapshot.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                final progress =
                                    progressSnapshot.data!.data();
                                final completed =
                                    progress?['completed'] == true;
                                final points = progress?['points'] ?? 0;
                                final badgeId = progress?['badgeId'];

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Your points: $points'),
                                    const SizedBox(height: 6),
                                    Text(
                                      completed
                                          ? 'Status: Completed'
                                          : 'Status: Not completed',
                                    ),
                                    if (completed && badgeId != null) ...[
                                      const SizedBox(height: 6),
                                      Text('Badge: $badgeId'),
                                    ],
                                    const SizedBox(height: 18),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: isCompleting
                                            ? null
                                            : completeChallenge,
                                        child: isCompleting
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : Text(
                                                completed
                                                    ? 'Check Completion Again'
                                                    : 'Complete Challenge',
                                              ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                            if (completionMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(completionMessage!),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                buildCoachCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
