import 'package:flutter/foundation.dart';

abstract class PushPermissionController extends ChangeNotifier {
  bool get needsPermission;
  Future<void> enable();
}
