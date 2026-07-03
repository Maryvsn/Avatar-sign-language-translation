import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sign_sense.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        full_name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  // ✅ Hash password before storing
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  // ✅ Register new user
  Future<Map<String, dynamic>> registerUser({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final db = await database;

      // Check if email already exists
      final existing = await db.query(
        'users',
        where: 'email = ?',
        whereArgs: [email.toLowerCase().trim()],
      );

      if (existing.isNotEmpty) {
        return {'success': false, 'message': 'هذا الإيميل مسجّل من قبل'};
      }

      await db.insert('users', {
        'full_name': fullName.trim(),
        'email': email.toLowerCase().trim(),
        'password': _hashPassword(password),
        'created_at': DateTime.now().toIso8601String(),
      });

      return {'success': true, 'message': 'تم إنشاء الحساب بنجاح'};
    } catch (e) {
      return {'success': false, 'message': 'حدث خطأ: $e'};
    }
  }

  // ✅ Login user
  Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final db = await database;

      final result = await db.query(
        'users',
        where: 'email = ? AND password = ?',
        whereArgs: [
          email.toLowerCase().trim(),
          _hashPassword(password),
        ],
      );

      if (result.isEmpty) {
        return {
          'success': false,
          'message': 'الإيميل أو الباسورد غلط',
        };
      }

      return {'success': true, 'user': result.first};
    } catch (e) {
      return {'success': false, 'message': 'حدث خطأ: $e'};
    }
  }

  // ✅ Get user by ID
  Future<Map<String, dynamic>?> getUserById(int id) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty ? result.first : null;
  }

  // ✅ Update user name and email
  Future<Map<String, dynamic>> updateUserInfo({
    required int id,
    required String fullName,
    required String email,
  }) async {
    try {
      final db = await database;

      // Check if email taken by another user
      final existing = await db.query(
        'users',
        where: 'email = ? AND id != ?',
        whereArgs: [email.toLowerCase().trim(), id],
      );

      if (existing.isNotEmpty) {
        return {'success': false, 'message': 'الإيميل ده مستخدم من حساب تاني'};
      }

      await db.update(
        'users',
        {
          'full_name': fullName.trim(),
          'email': email.toLowerCase().trim(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      return {'success': true, 'message': 'تم تحديث البيانات بنجاح'};
    } catch (e) {
      return {'success': false, 'message': 'حدث خطأ: $e'};
    }
  }

  // ✅ Change password
  Future<Map<String, dynamic>> changePassword({
    required int id,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final db = await database;

      // Verify current password
      final result = await db.query(
        'users',
        where: 'id = ? AND password = ?',
        whereArgs: [id, _hashPassword(currentPassword)],
      );

      if (result.isEmpty) {
        return {'success': false, 'message': 'الباسورد الحالي غلط'};
      }

      await db.update(
        'users',
        {'password': _hashPassword(newPassword)},
        where: 'id = ?',
        whereArgs: [id],
      );

      return {'success': true, 'message': 'تم تغيير الباسورد بنجاح'};
    } catch (e) {
      return {'success': false, 'message': 'حدث خطأ: $e'};
    }
  }

  Future close() async {
    final db = await database;
    db.close();
  }
}
