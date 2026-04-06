// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugin.platform;

import static io.flutter.Build.API_LEVELS;

import android.app.Activity;
import android.app.ActivityManager.TaskDescription;
import android.content.ClipData;
import android.content.ClipDescription;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.res.AssetFileDescriptor;
import android.net.Uri;
import android.os.Build;
import android.view.HapticFeedbackConstants;
import android.view.SoundEffectConstants;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import androidx.activity.OnBackPressedDispatcherOwner;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.VisibleForTesting;
import androidx.core.view.WindowInsetsControllerCompat;
import io.flutter.Log;
import io.flutter.embedding.engine.systemchannels.PlatformChannel;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.List;

/**
 * Local patch of Flutter's PlatformPlugin that avoids Android 15 deprecated system bar color APIs.
 */
public class PlatformPlugin {
  public static final int DEFAULT_SYSTEM_UI =
      View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN;

  private final Activity activity;
  private final PlatformChannel platformChannel;
  @Nullable private final PlatformPluginDelegate platformPluginDelegate;
  private PlatformChannel.SystemChromeStyle currentTheme;
  private int mEnabledOverlays;
  private static final String TAG = "PlatformPlugin";

  public interface PlatformPluginDelegate {
    boolean popSystemNavigator();

    default void setFrameworkHandlesBack(boolean frameworkHandlesBack) {}
  }

  @VisibleForTesting
  final PlatformChannel.PlatformMessageHandler mPlatformMessageHandler =
      new PlatformChannel.PlatformMessageHandler() {
        @Override
        public void playSystemSound(@NonNull PlatformChannel.SoundType soundType) {
          PlatformPlugin.this.playSystemSound(soundType);
        }

        @Override
        public void vibrateHapticFeedback(
            @NonNull PlatformChannel.HapticFeedbackType feedbackType) {
          PlatformPlugin.this.vibrateHapticFeedback(feedbackType);
        }

        @Override
        public void setPreferredOrientations(int androidOrientation) {
          setSystemChromePreferredOrientations(androidOrientation);
        }

        @Override
        public void setApplicationSwitcherDescription(
            @NonNull PlatformChannel.AppSwitcherDescription description) {
          setSystemChromeApplicationSwitcherDescription(description);
        }

        @Override
        public void showSystemOverlays(@NonNull List<PlatformChannel.SystemUiOverlay> overlays) {
          setSystemChromeEnabledSystemUIOverlays(overlays);
        }

        @Override
        public void showSystemUiMode(@NonNull PlatformChannel.SystemUiMode mode) {
          setSystemChromeEnabledSystemUIMode(mode);
        }

        @Override
        public void setSystemUiChangeListener() {
          setSystemChromeChangeListener();
        }

        @Override
        public void restoreSystemUiOverlays() {
          restoreSystemChromeSystemUIOverlays();
        }

        @Override
        public void setSystemUiOverlayStyle(
            @NonNull PlatformChannel.SystemChromeStyle systemUiOverlayStyle) {
          setSystemChromeSystemUIOverlayStyle(systemUiOverlayStyle);
        }

        @Override
        public void setFrameworkHandlesBack(boolean frameworkHandlesBack) {
          PlatformPlugin.this.setFrameworkHandlesBack(frameworkHandlesBack);
        }

        @Override
        public void popSystemNavigator() {
          PlatformPlugin.this.popSystemNavigator();
        }

        @Override
        public CharSequence getClipboardData(
            @Nullable PlatformChannel.ClipboardContentFormat format) {
          return PlatformPlugin.this.getClipboardData(format);
        }

        @Override
        public void setClipboardData(@NonNull String text) {
          PlatformPlugin.this.setClipboardData(text);
        }

        @Override
        public boolean clipboardHasStrings() {
          return PlatformPlugin.this.clipboardHasStrings();
        }

        @Override
        public void share(@NonNull String text) {
          PlatformPlugin.this.share(text);
        }
      };

  public PlatformPlugin(@NonNull Activity activity, @NonNull PlatformChannel platformChannel) {
    this(activity, platformChannel, null);
  }

  public PlatformPlugin(
      @NonNull Activity activity,
      @NonNull PlatformChannel platformChannel,
      @Nullable PlatformPluginDelegate delegate) {
    this.activity = activity;
    this.platformChannel = platformChannel;
    this.platformChannel.setPlatformMessageHandler(mPlatformMessageHandler);
    this.platformPluginDelegate = delegate;
    mEnabledOverlays = DEFAULT_SYSTEM_UI;
  }

  public void destroy() {
    this.platformChannel.setPlatformMessageHandler(null);
  }

  private void playSystemSound(@NonNull PlatformChannel.SoundType soundType) {
    if (soundType == PlatformChannel.SoundType.CLICK) {
      View view = activity.getWindow().getDecorView();
      view.playSoundEffect(SoundEffectConstants.CLICK);
    }
  }

  @VisibleForTesting
  void vibrateHapticFeedback(@NonNull PlatformChannel.HapticFeedbackType feedbackType) {
    View view = activity.getWindow().getDecorView();
    switch (feedbackType) {
      case STANDARD:
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        break;
      case LIGHT_IMPACT:
        view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
        break;
      case MEDIUM_IMPACT:
        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
        break;
      case HEAVY_IMPACT:
        view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK);
        break;
      case SELECTION_CLICK:
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
        break;
      case SUCCESS_NOTIFICATION:
        if (Build.VERSION.SDK_INT >= API_LEVELS.API_30) {
          view.performHapticFeedback(HapticFeedbackConstants.CONFIRM);
        }
        break;
      case WARNING_NOTIFICATION:
        if (Build.VERSION.SDK_INT >= API_LEVELS.API_30) {
          view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
        }
        break;
      case ERROR_NOTIFICATION:
        if (Build.VERSION.SDK_INT >= API_LEVELS.API_30) {
          view.performHapticFeedback(HapticFeedbackConstants.REJECT);
        }
        break;
    }
  }

  private void setSystemChromePreferredOrientations(int androidOrientation) {
    activity.setRequestedOrientation(androidOrientation);
  }

  @SuppressWarnings("deprecation")
  private void setSystemChromeApplicationSwitcherDescription(
      PlatformChannel.AppSwitcherDescription description) {
    if (Build.VERSION.SDK_INT < API_LEVELS.API_28) {
      activity.setTaskDescription(
          new TaskDescription(description.label, /* icon= */ null, description.color));
    } else {
      TaskDescription taskDescription =
          new TaskDescription(description.label, 0, description.color);
      activity.setTaskDescription(taskDescription);
    }
  }

  private void setSystemChromeChangeListener() {
    View decorView = activity.getWindow().getDecorView();
    decorView.setOnSystemUiVisibilityChangeListener(
        visibility ->
            decorView.post(
                () -> platformChannel.systemChromeChanged(
                    (visibility & View.SYSTEM_UI_FLAG_FULLSCREEN) == 0)));
  }

  private void setSystemChromeEnabledSystemUIMode(PlatformChannel.SystemUiMode systemUiMode) {
    int enabledOverlays;

    if (systemUiMode == PlatformChannel.SystemUiMode.LEAN_BACK) {
      enabledOverlays =
          View.SYSTEM_UI_FLAG_LAYOUT_STABLE
              | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
              | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
              | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
              | View.SYSTEM_UI_FLAG_FULLSCREEN;
    } else if (systemUiMode == PlatformChannel.SystemUiMode.IMMERSIVE) {
      enabledOverlays =
          View.SYSTEM_UI_FLAG_IMMERSIVE
              | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
              | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
              | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
              | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
              | View.SYSTEM_UI_FLAG_FULLSCREEN;
    } else if (systemUiMode == PlatformChannel.SystemUiMode.IMMERSIVE_STICKY) {
      enabledOverlays =
          View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
              | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
              | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
              | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
              | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
              | View.SYSTEM_UI_FLAG_FULLSCREEN;
    } else if (systemUiMode == PlatformChannel.SystemUiMode.EDGE_TO_EDGE
        && Build.VERSION.SDK_INT >= API_LEVELS.API_29) {
      enabledOverlays =
          View.SYSTEM_UI_FLAG_LAYOUT_STABLE
              | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
              | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN;
    } else {
      return;
    }

    mEnabledOverlays = enabledOverlays;
    updateSystemUiOverlays();
  }

  private void setSystemChromeEnabledSystemUIOverlays(
      List<PlatformChannel.SystemUiOverlay> overlaysToShow) {
    int enabledOverlays =
        DEFAULT_SYSTEM_UI
            | View.SYSTEM_UI_FLAG_FULLSCREEN
            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION;

    if (overlaysToShow.isEmpty()) {
      enabledOverlays |= View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY;
    }

    for (int i = 0; i < overlaysToShow.size(); ++i) {
      PlatformChannel.SystemUiOverlay overlayToShow = overlaysToShow.get(i);
      switch (overlayToShow) {
        case TOP_OVERLAYS:
          enabledOverlays &= ~View.SYSTEM_UI_FLAG_FULLSCREEN;
          break;
        case BOTTOM_OVERLAYS:
          enabledOverlays &= ~View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION;
          enabledOverlays &= ~View.SYSTEM_UI_FLAG_HIDE_NAVIGATION;
          break;
      }
    }

    mEnabledOverlays = enabledOverlays;
    updateSystemUiOverlays();
  }

  public void updateSystemUiOverlays() {
    activity.getWindow().getDecorView().setSystemUiVisibility(mEnabledOverlays);
    if (currentTheme != null) {
      setSystemChromeSystemUIOverlayStyle(currentTheme);
    }
  }

  private void restoreSystemChromeSystemUIOverlays() {
    updateSystemUiOverlays();
  }

  private void setSystemChromeSystemUIOverlayStyle(
      PlatformChannel.SystemChromeStyle systemChromeStyle) {
    Window window = activity.getWindow();
    View view = window.getDecorView();
    WindowInsetsControllerCompat windowInsetsControllerCompat =
        new WindowInsetsControllerCompat(window, view);

    if (Build.VERSION.SDK_INT < API_LEVELS.API_30) {
      window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
      window.clearFlags(
          WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS
              | WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION);
    }

    if (systemChromeStyle.statusBarIconBrightness != null) {
      switch (systemChromeStyle.statusBarIconBrightness) {
        case DARK:
          windowInsetsControllerCompat.setAppearanceLightStatusBars(true);
          break;
        case LIGHT:
          windowInsetsControllerCompat.setAppearanceLightStatusBars(false);
          break;
      }
    }

    if (systemChromeStyle.systemStatusBarContrastEnforced != null
        && Build.VERSION.SDK_INT >= API_LEVELS.API_29) {
      window.setStatusBarContrastEnforced(systemChromeStyle.systemStatusBarContrastEnforced);
    }

    if (Build.VERSION.SDK_INT >= API_LEVELS.API_26
        && systemChromeStyle.systemNavigationBarIconBrightness != null) {
      switch (systemChromeStyle.systemNavigationBarIconBrightness) {
        case DARK:
          windowInsetsControllerCompat.setAppearanceLightNavigationBars(true);
          break;
        case LIGHT:
          windowInsetsControllerCompat.setAppearanceLightNavigationBars(false);
          break;
      }
    }

    if (systemChromeStyle.systemNavigationBarContrastEnforced != null
        && Build.VERSION.SDK_INT >= API_LEVELS.API_29) {
      window.setNavigationBarContrastEnforced(
          systemChromeStyle.systemNavigationBarContrastEnforced);
    }

    currentTheme = systemChromeStyle;
  }

  private void setFrameworkHandlesBack(boolean frameworkHandlesBack) {
    if (platformPluginDelegate != null) {
      platformPluginDelegate.setFrameworkHandlesBack(frameworkHandlesBack);
    }
  }

  private void popSystemNavigator() {
    if (platformPluginDelegate != null && platformPluginDelegate.popSystemNavigator()) {
      return;
    }

    if (activity instanceof OnBackPressedDispatcherOwner) {
      ((OnBackPressedDispatcherOwner) activity).getOnBackPressedDispatcher().onBackPressed();
    } else {
      activity.finish();
    }
  }

  private CharSequence getClipboardData(PlatformChannel.ClipboardContentFormat format) {
    ClipboardManager clipboard =
        (ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE);

    if (!clipboard.hasPrimaryClip()) {
      return null;
    }

    CharSequence itemText = null;
    try {
      ClipData clip = clipboard.getPrimaryClip();
      if (clip == null) {
        return null;
      }
      if (format == null || format == PlatformChannel.ClipboardContentFormat.PLAIN_TEXT) {
        ClipData.Item item = clip.getItemAt(0);
        itemText = item.getText();
        if (itemText == null) {
          Uri itemUri = item.getUri();

          if (itemUri == null) {
            Log.w(
                TAG, "Clipboard item contained no textual content nor a URI to retrieve it from.");
            return null;
          }

          String uriScheme = itemUri.getScheme();
          if (!"content".equals(uriScheme)) {
            Log.w(
                TAG,
                "Clipboard item contains a Uri with scheme '" + uriScheme + "'that is unhandled.");
            return null;
          }

          AssetFileDescriptor assetFileDescriptor =
              activity.getContentResolver().openTypedAssetFileDescriptor(itemUri, "text/*", null);
          itemText = item.coerceToText(activity);
          if (assetFileDescriptor != null) {
            assetFileDescriptor.close();
          }
        }

        return itemText;
      }
    } catch (SecurityException e) {
      Log.w(
          TAG,
          "Attempted to get clipboard data that requires additional permission(s).\n"
              + "See the exception details for which permission(s) are required, and consider adding them to your Android Manifest as described in:\n"
              + "https://developer.android.com/guide/topics/permissions/overview",
          e);
      return null;
    } catch (FileNotFoundException e) {
      Log.w(TAG, "Clipboard text was unable to be received from content URI.");
      return null;
    } catch (IOException e) {
      Log.w(TAG, "Failed to close AssetFileDescriptor while trying to read text from URI.", e);
      return itemText;
    }

    return null;
  }

  private void setClipboardData(String text) {
    ClipboardManager clipboard =
        (ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE);
    ClipData clip = ClipData.newPlainText("text label?", text);
    clipboard.setPrimaryClip(clip);
  }

  private boolean clipboardHasStrings() {
    ClipboardManager clipboard =
        (ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE);
    if (!clipboard.hasPrimaryClip()) {
      return false;
    }
    ClipDescription description = clipboard.getPrimaryClipDescription();
    if (description == null) {
      return false;
    }
    return description.hasMimeType("text/*");
  }

  private void share(@NonNull String text) {
    Intent intent = new Intent();
    intent.setAction(Intent.ACTION_SEND);
    intent.setType("text/plain");
    intent.putExtra(Intent.EXTRA_TEXT, text);
    activity.startActivity(Intent.createChooser(intent, null));
  }
}
