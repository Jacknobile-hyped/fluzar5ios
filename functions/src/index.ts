import * as admin from 'firebase-admin';

// Initialize Firebase Admin
admin.initializeApp();

// Import and export the scheduled posts function
import { publishScheduledPost } from './scheduled-posts';

// Import and export the Cloudflare helper functions
import { getCloudflareSignedUrl } from './cloudflare-helper';

// Import and export the daily analysis reset functions
import { resetDailyAnalysisLimit, cleanupOldAnalysisRecords } from './daily-analysis-reset';

export { 
  publishScheduledPost,
  getCloudflareSignedUrl,
  resetDailyAnalysisLimit,
  cleanupOldAnalysisRecords
};