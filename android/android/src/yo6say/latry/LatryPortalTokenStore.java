package yo6say.latry;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.util.Log;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.UUID;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Secure storage for the SVXportal / Latry API bearer token.
 *
 * The token is encrypted with an AES key stored in Android Keystore.
 * SharedPreferences only contains ciphertext + IV.
 */
public final class LatryPortalTokenStore {
    private static final String TAG = "LatryPortalTokenStore";

    private static final String KEYSTORE = "AndroidKeyStore";
    private static final String KEY_ALIAS = "si.pmr446.latry.portal_token";

    private static final String PREFS_NAME = "LatryPortalSecurePrefs";
    private static final String PREF_TOKEN = "portal_token_ciphertext";
    private static final String PREF_IV = "portal_token_iv";
    private static final String PREF_DEVICE_ID = "portal_device_id";
    private static final String PREF_CALLSIGN = "portal_token_callsign";

    private static final String CIPHER = "AES/GCM/NoPadding";

    private LatryPortalTokenStore() {}

    private static SecretKey getOrCreateKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance(KEYSTORE);
        keyStore.load(null);

        if (keyStore.containsAlias(KEY_ALIAS)) {
            return (SecretKey) keyStore.getKey(KEY_ALIAS, null);
        }

        KeyGenerator generator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                KEYSTORE
        );

        generator.init(
                new KeyGenParameterSpec.Builder(
                        KEY_ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT
                                | KeyProperties.PURPOSE_DECRYPT
                )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        );

        return generator.generateKey();
    }

    public static String getOrCreateDeviceId(Context context) {
        if (context == null) {
            return "";
        }

        SharedPreferences prefs = context.getSharedPreferences(
                PREFS_NAME,
                Context.MODE_PRIVATE
        );

        String deviceId = prefs.getString(PREF_DEVICE_ID, "");

        if (!deviceId.isEmpty()) {
            return deviceId;
        }

        deviceId = UUID.randomUUID().toString();

        prefs.edit()
                .putString(PREF_DEVICE_ID, deviceId)
                .commit();

        return deviceId;
    }

    public static boolean hasTokenForCallsign(Context context, String callsign) {
        if (context == null || callsign == null) {
            return false;
        }

        String wanted = callsign.trim().toUpperCase();

        SharedPreferences prefs = context.getSharedPreferences(
                PREFS_NAME,
                Context.MODE_PRIVATE
        );

        String stored = prefs.getString(PREF_CALLSIGN, "");

        return !wanted.isEmpty()
                && wanted.equalsIgnoreCase(stored)
                && hasToken(context);
    }

    public static boolean saveTokenForCallsign(
            Context context,
            String callsign,
            String token) {

        if (!saveToken(context, token)) {
            return false;
        }

        String normalized = callsign != null
                ? callsign.trim().toUpperCase()
                : "";

        return context.getSharedPreferences(
                PREFS_NAME,
                Context.MODE_PRIVATE
        )
        .edit()
        .putString(PREF_CALLSIGN, normalized)
        .commit();
    }

    public static boolean saveToken(Context context, String token) {
        if (context == null) {
            return false;
        }

        String normalized = token != null ? token.trim() : "";

        if (normalized.isEmpty()) {
            clearToken(context);
            return true;
        }

        try {
            Cipher cipher = Cipher.getInstance(CIPHER);
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey());

            byte[] ciphertext = cipher.doFinal(
                    normalized.getBytes(StandardCharsets.UTF_8)
            );

            String encodedCiphertext = Base64.encodeToString(
                    ciphertext,
                    Base64.NO_WRAP
            );

            String encodedIv = Base64.encodeToString(
                    cipher.getIV(),
                    Base64.NO_WRAP
            );

            SharedPreferences prefs = context.getSharedPreferences(
                    PREFS_NAME,
                    Context.MODE_PRIVATE
            );

            return prefs.edit()
                    .putString(PREF_TOKEN, encodedCiphertext)
                    .putString(PREF_IV, encodedIv)
                    .commit();

        } catch (Exception e) {
            Log.e(TAG, "Failed to save portal token", e);
            return false;
        }
    }

    public static String loadToken(Context context) {
        if (context == null) {
            return "";
        }

        SharedPreferences prefs = context.getSharedPreferences(
                PREFS_NAME,
                Context.MODE_PRIVATE
        );

        String encodedCiphertext = prefs.getString(PREF_TOKEN, "");
        String encodedIv = prefs.getString(PREF_IV, "");

        if (encodedCiphertext.isEmpty() || encodedIv.isEmpty()) {
            return "";
        }

        try {
            byte[] ciphertext = Base64.decode(
                    encodedCiphertext,
                    Base64.NO_WRAP
            );

            byte[] iv = Base64.decode(
                    encodedIv,
                    Base64.NO_WRAP
            );

            KeyStore keyStore = KeyStore.getInstance(KEYSTORE);
            keyStore.load(null);

            SecretKey key = (SecretKey) keyStore.getKey(KEY_ALIAS, null);

            if (key == null) {
                Log.w(TAG, "Portal token key is missing");
                clearToken(context);
                return "";
            }

            Cipher cipher = Cipher.getInstance(CIPHER);

            cipher.init(
                    Cipher.DECRYPT_MODE,
                    key,
                    new GCMParameterSpec(128, iv)
            );

            byte[] plaintext = cipher.doFinal(ciphertext);

            return new String(
                    plaintext,
                    StandardCharsets.UTF_8
            );

        } catch (Exception e) {
            Log.e(TAG, "Failed to load portal token", e);

            /*
             * This may happen after restoring app data onto another device,
             * because Android Keystore keys are device-bound.
             */
            clearToken(context);

            return "";
        }
    }

    public static boolean hasToken(Context context) {
        return !loadToken(context).isEmpty();
    }

    public static void clearToken(Context context) {
        if (context == null) {
            return;
        }

        context.getSharedPreferences(
                PREFS_NAME,
                Context.MODE_PRIVATE
        )
        .edit()
        .remove(PREF_TOKEN)
        .remove(PREF_IV)
        .remove(PREF_CALLSIGN)
        .apply();
    }
}
