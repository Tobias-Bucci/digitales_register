"""Shared source/archive Firebase checks; never print configuration contents."""
import plistlib

PROJECT_ID = 'digitales-register-ca085'
BUNDLE_ID = 'it.bucci.digitalesregister'
APP_ID = '1:750743736341:ios:2d070d4633f6f209e57e1c'
PRIVACY_DEFAULTS = (
    'FirebaseAutomaticScreenReportingEnabled',
    'FirebaseCrashlyticsCollectionEnabled',
    'FIREBASE_ANALYTICS_COLLECTION_ENABLED',
    'GOOGLE_ANALYTICS_IDFA_COLLECTION_ENABLED',
    'GOOGLE_ANALYTICS_DEFAULT_ALLOW_ANALYTICS_STORAGE',
    'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE',
    'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA',
    'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS',
)


def configuration_errors(data):
    try:
        config = plistlib.loads(data)
    except Exception:
        # Parser errors can include fragments of the input. Keep CI logs private.
        return ['Invalid Firebase plist (cannot parse configuration)']
    if not isinstance(config, dict):
        return ['Invalid Firebase plist (expected a dictionary)']
    errors = []
    for key, expected in [('PROJECT_ID', PROJECT_ID), ('BUNDLE_ID', BUNDLE_ID),
                          ('GOOGLE_APP_ID', APP_ID), ('GCM_SENDER_ID', '750743736341')]:
        if config.get(key) != expected:
            errors.append(f'Firebase configuration mismatch: {key}')
    if not isinstance(config.get('API_KEY'), str) or not config['API_KEY'].strip():
        errors.append('Firebase configuration missing API_KEY')
    return errors


def privacy_errors(info):
    return [f'Privacy default must be Boolean false: {key}'
            for key in PRIVACY_DEFAULTS if info.get(key) is not False]
