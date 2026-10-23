package it.bucci.digitalesregister

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Biometric prompt used by the app lock on Android.
 *
 * `biometric_storage` protects its storage file with an AndroidKeyStore key created for strong
 * (Class 3) biometrics, and androidx.biometric refuses crypto-based authentication with weak
 * (Class 2) biometrics. Most Android face recognition is Class 2, so devices that only offer
 * face unlock could not use the biometric app lock at all.
 *
 * The app lock only needs to know whether the user authenticated, not to unlock a secret, so it
 * asks [BiometricPrompt] directly and accepts every enrolled biometric.
 */
class BiometricAppLockChannel(
    private val activity: FragmentActivity,
) : MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var prompt: BiometricPrompt? = null
    private var pendingResult: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
        val pending = pendingResult
        pendingResult = null
        prompt?.cancelAuthentication()
        prompt = null
        pending?.error("canceled", "Authentication was canceled.", null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canAuthenticate" -> result.success(availabilityName())
            "authenticate" -> authenticate(call, result)
            else -> result.notImplemented()
        }
    }

    private fun availabilityName(): String {
        return when (
            BiometricManager.from(activity)
                .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)
        ) {
            BiometricManager.BIOMETRIC_SUCCESS -> "success"
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "errorHwUnavailable"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "errorNoBiometricEnrolled"
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> "errorNoHardware"
            BiometricManager.BIOMETRIC_STATUS_UNKNOWN -> "statusUnknown"
            else -> "unsupported"
        }
    }

    private fun authenticate(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("in_progress", "An authentication request is already running.", null)
            return
        }

        val title = call.argument<String>("title")
        if (title.isNullOrBlank()) {
            result.error("invalid_args", "Missing prompt title.", null)
            return
        }

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setNegativeButtonText(call.argument<String>("negativeButton") ?: "Cancel")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
            .setConfirmationRequired(call.argument<Boolean>("confirmationRequired") ?: false)
            .apply {
                call.argument<String>("subtitle")?.let { setSubtitle(it) }
                call.argument<String>("description")?.let { setDescription(it) }
            }
            .build()

        val biometricPrompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult,
                ) {
                    complete { it.success(true) }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    complete {
                        it.error(
                            if (isUserCancellation(errorCode)) "canceled" else "failed",
                            errString.toString(),
                            null,
                        )
                    }
                }
            },
        )

        pendingResult = result
        prompt = biometricPrompt
        try {
            biometricPrompt.authenticate(promptInfo)
        } catch (error: Throwable) {
            pendingResult = null
            prompt = null
            result.error("failed", error.message, null)
        }
    }

    private fun complete(onResult: (MethodChannel.Result) -> Unit) {
        val pending = pendingResult ?: return
        pendingResult = null
        prompt = null
        onResult(pending)
    }

    private fun isUserCancellation(errorCode: Int): Boolean {
        return errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
            errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
            errorCode == BiometricPrompt.ERROR_CANCELED
    }

    private companion object {
        const val CHANNEL_NAME = "dr/biometric_app_lock"
    }
}
