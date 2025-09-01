import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { getStorage } from 'firebase-admin/storage';

admin.initializeApp();
const storage = getStorage();

interface PostData {
  video_path: string;
  thumbnail_path?: string;
  platforms: string[];
  accounts: Record<string, any>;
  status: string;
  scheduled_time: number;
  description?: string;
  title?: string;
}

export const publishScheduledPost = functions.https.onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const data = request.data as {
    postId: string;
    userId: string;
    postData: PostData;
  };

  const { postData } = data;
  
  try {
    // Download video from Firebase Storage
    const videoPath = postData.video_path;
    const videoFile = storage.bucket().file(videoPath);
    const [signedVideoUrl] = await videoFile.getSignedUrl({
      action: 'read',
      expires: Date.now() + 3600000, // 1 hour
    });

    // Download thumbnail if exists
    let signedThumbnailUrl: string | null = null;
    if (postData.thumbnail_path) {
      const thumbnailFile = storage.bucket().file(postData.thumbnail_path);
      const [url] = await thumbnailFile.getSignedUrl({
        action: 'read',
        expires: Date.now() + 3600000,
      });
      signedThumbnailUrl = url;
    }

    // Publish to each platform
    const platforms = postData.platforms || [];
    const accounts = postData.accounts || {};
    const results: Array<{ platform: string; success: boolean; message?: string }> = [];

    for (const platform of platforms) {
      const account = accounts[platform];
      if (!account) continue;

      try {
        switch (platform) {
          case 'YouTube':
            // TODO: Implement YouTube upload using signedVideoUrl
            results.push({ platform, success: false, message: 'YouTube upload not implemented yet' });
            break;
          case 'TikTok':
            // TODO: Implement TikTok upload using signedVideoUrl
            results.push({ platform, success: false, message: 'TikTok upload not implemented yet' });
            break;
          case 'Instagram':
            // TODO: Implement Instagram upload using signedVideoUrl
            results.push({ platform, success: false, message: 'Instagram upload not implemented yet' });
            break;
          case 'Facebook':
            // TODO: Implement Facebook upload using signedVideoUrl
            results.push({ platform, success: false, message: 'Facebook upload not implemented yet' });
            break;
          case 'Twitter':
            // TODO: Implement Twitter upload using signedVideoUrl
            results.push({ platform, success: false, message: 'Twitter upload not implemented yet' });
            break;
        }
      } catch (error) {
        results.push({ 
          platform, 
          success: false, 
          message: error instanceof Error ? error.message : 'Unknown error occurred' 
        });
      }
    }

    return { success: true, results, videoUrl: signedVideoUrl, thumbnailUrl: signedThumbnailUrl };
  } catch (error) {
    console.error('Error publishing scheduled post:', error);
    throw new functions.https.HttpsError(
      'internal', 
      'Error publishing post', 
      error instanceof Error ? error.message : 'Unknown error occurred'
    );
  }
}); 