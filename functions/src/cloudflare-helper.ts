import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import axios from 'axios';

// Cloudflare S3 credentials from storage.md
const CLOUDFLARE_ACCOUNT_ID = '3cd9209da4d0a20e311d486fc37f1a71';
const CLOUDFLARE_ACCESS_KEY_ID = '5e181628bad7dc5481c92c6f3899efd6';
const CLOUDFLARE_SECRET_ACCESS_KEY = '457366ba03debc4749681c3295b1f3afb10d438df3ae58e2ac883b5fb1b9e5b1';
const CLOUDFLARE_BUCKET_NAME = 'videos';

/**
 * Function to get a pre-signed URL for Cloudflare R2 storage
 * This makes the integration with the worker secure
 */
export const getCloudflareSignedUrl = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'The function must be called while authenticated.'
    );
  }

  try {
    const { fileName, operation } = data;
    
    if (!fileName || !operation) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'The function requires fileName and operation parameters.'
      );
    }

    if (operation !== 'read' && operation !== 'write') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Operation must be either "read" or "write".'
      );
    }

    // Generate authentication for Worker request
    const apiKey = await admin.app().options.apiKey;
    if (!apiKey) {
      throw new functions.https.HttpsError(
        'internal',
        'Could not retrieve Firebase API key'
      );
    }

    // Make request to Cloudflare Worker
    const response = await axios.post(
      'https://plain-star-669f.giuseppemaria162.workers.dev',
      {
        fileName: fileName,
        operation: operation,
        userId: context.auth.uid // Include user ID for additional security
      },
      {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
          'X-Firebase-Auth': context.auth.token.uid,
        }
      }
    );

    // Return the signed URL received from the worker
    return {
      signedUrl: response.data.signedUrl,
      bucketName: CLOUDFLARE_BUCKET_NAME,
      accountId: CLOUDFLARE_ACCOUNT_ID
    };
  } catch (error) {
    console.error('Error generating Cloudflare signed URL:', error);
    
    // Properly format the error response
    let errorMessage = 'Unknown error occurred';
    if (axios.isAxiosError(error)) {
      errorMessage = `Worker error: ${error.message}`;
      if (error.response) {
        errorMessage += ` Status: ${error.response.status}`;
      }
    } else if (error instanceof Error) {
      errorMessage = error.message;
    }
    
    throw new functions.https.HttpsError('internal', errorMessage);
  }
}); 