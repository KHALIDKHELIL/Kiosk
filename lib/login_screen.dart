import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool isSeeding = false;

 Future<void> signIn() async {
    // 1. NEW: Check for empty fields first
    if (emailController.text.trim().isEmpty || passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both email and password.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Login failed'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- TEMPORARY AUTH SEEDER ---
  Future<void> seedAuthAccounts() async {
    setState(() => isSeeding = true);
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;

    try {
      // 1. Create Admin Account
      final adminCred = await auth.createUserWithEmailAndPassword(
        email: 'admin@kiosk.com',
        password: 'password123',
      );
      // Set role in Firestore
      await db.collection('users').doc(adminCred.user!.uid).set({'role': 'admin'});

      // 2. Create Worker Account
      // Note: We sign out the admin immediately so we can create the worker
      await auth.signOut(); 
      final workerCred = await auth.createUserWithEmailAndPassword(
        email: 'worker@kiosk.com',
        password: 'password123',
      );
      // Set role in Firestore
      await db.collection('users').doc(workerCred.user!.uid).set({'role': 'worker'});

      // Sign out again so you can log in normally
      await auth.signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Accounts created! You can now log in.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error (Users might already exist): $e'), backgroundColor: Colors.orange),
        );
      }
    } finally {
      if (mounted) setState(() => isSeeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            elevation: 8,
            // FIX: Removed padding from Card, wrapped Column in Padding widget
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront, size: 64, color: Colors.blue),
                  const SizedBox(height: 16),
                  Text('Kiosk POS Login', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 32),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    obscureText: true,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isLoading ? null : signIn,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('SIGN IN'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}