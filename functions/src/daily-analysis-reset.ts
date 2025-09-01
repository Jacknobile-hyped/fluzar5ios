import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// Cloud Function per resettare il limite giornaliero delle analisi AI
// Viene eseguita ogni giorno alle 00:00 UTC
export const resetDailyAnalysisLimit = functions.pubsub
  .schedule('0 0 * * *') // Ogni giorno alle 00:00 UTC
  .timeZone('UTC')
  .onRun(async (context) => {
    try {
      console.log('Iniziando reset del limite giornaliero analisi AI...');
      
      const db = admin.database();
      const usersRef = db.ref('users/users');
      
      // Ottieni tutti gli utenti
      const usersSnapshot = await usersRef.once('value');
      const users = usersSnapshot.val();
      
      if (!users) {
        console.log('Nessun utente trovato');
        return null;
      }
      
      let resetCount = 0;
      const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
      
      // Itera su tutti gli utenti
      for (const [userId, userData] of Object.entries(users)) {
        try {
          const user = userData as any;
          
          // Controlla se l'utente ha dati di analisi giornaliere
          if (user.daily_analysis_stats) {
            const dailyStatsRef = db.ref(`users/users/${userId}/daily_analysis_stats`);
            
            // Ottieni tutti i record giornalieri
            const dailyStatsSnapshot = await dailyStatsRef.once('value');
            const dailyStats = dailyStatsSnapshot.val();
            
            if (dailyStats) {
              // Rimuovi tutti i record tranne quello di oggi (se esiste)
              const updates: { [key: string]: any } = {};
              
              for (const [date, stats] of Object.entries(dailyStats)) {
                if (date !== today) {
                  updates[`${date}`] = null; // Rimuovi il record
                }
              }
              
              // Applica gli aggiornamenti
              if (Object.keys(updates).length > 0) {
                await dailyStatsRef.update(updates);
                resetCount++;
                console.log(`Reset completato per utente ${userId}`);
              }
            }
          }
        } catch (userError) {
          console.error(`Errore nel processare utente ${userId}:`, userError);
          // Continua con il prossimo utente
        }
      }
      
      console.log(`Reset completato per ${resetCount} utenti`);
      return { success: true, resetCount };
      
    } catch (error) {
      console.error('Errore durante il reset del limite giornaliero:', error);
      throw error;
    }
  });

// Cloud Function per pulire i record vecchi (opzionale, per mantenere il database pulito)
export const cleanupOldAnalysisRecords = functions.pubsub
  .schedule('0 2 * * 0') // Ogni domenica alle 02:00 UTC
  .timeZone('UTC')
  .onRun(async (context) => {
    try {
      console.log('Iniziando pulizia record analisi vecchi...');
      
      const db = admin.database();
      const usersRef = db.ref('users/users');
      
      // Ottieni tutti gli utenti
      const usersSnapshot = await usersRef.once('value');
      const users = usersSnapshot.val();
      
      if (!users) {
        console.log('Nessun utente trovato');
        return null;
      }
      
      let cleanupCount = 0;
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
      const cutoffDate = thirtyDaysAgo.toISOString().split('T')[0];
      
      // Itera su tutti gli utenti
      for (const [userId, userData] of Object.entries(users)) {
        try {
          const user = userData as any;
          
          // Controlla se l'utente ha dati di analisi giornaliere
          if (user.daily_analysis_stats) {
            const dailyStatsRef = db.ref(`users/users/${userId}/daily_analysis_stats`);
            
            // Ottieni tutti i record giornalieri
            const dailyStatsSnapshot = await dailyStatsRef.once('value');
            const dailyStats = dailyStatsSnapshot.val();
            
            if (dailyStats) {
              // Rimuovi i record più vecchi di 30 giorni
              const updates: { [key: string]: any } = {};
              
              for (const [date, stats] of Object.entries(dailyStats)) {
                if (date < cutoffDate) {
                  updates[`${date}`] = null; // Rimuovi il record
                }
              }
              
              // Applica gli aggiornamenti
              if (Object.keys(updates).length > 0) {
                await dailyStatsRef.update(updates);
                cleanupCount++;
                console.log(`Pulizia completata per utente ${userId}`);
              }
            }
          }
        } catch (userError) {
          console.error(`Errore nel processare utente ${userId}:`, userError);
          // Continua con il prossimo utente
        }
      }
      
      console.log(`Pulizia completata per ${cleanupCount} utenti`);
      return { success: true, cleanupCount };
      
    } catch (error) {
      console.error('Errore durante la pulizia dei record vecchi:', error);
      throw error;
    }
  }); 