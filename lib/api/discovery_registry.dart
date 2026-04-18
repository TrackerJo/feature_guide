import 'dart:io';

import 'package:feature_guide/api/feature_discovery_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Central catalog of every [DiscoveryTip].
///
/// Called once at app bootstrap (analogous to the legacy
/// `StartupDialogService.registerDefaults`). Tips registered here are the
/// canonical list; the legacy `StartupDialogService` now delegates to the
/// [FeatureDiscoveryService] singleton.
void registerAllDiscoveryTips() {
  final service = FeatureDiscoveryService();
  service.registerAll([]);
}

// ---------------------------------------------------------------------------
// Startup tips (onStartupTick)
// ---------------------------------------------------------------------------
