package dev.fluttercommunity.workmanager

import io.flutter.embedding.engine.FlutterEngine

/** Optional app hook after automatic plugin registration in a headless engine. */
interface BackgroundEngineConfigurator {
    fun configureBackgroundEngine(engine: FlutterEngine)
}
