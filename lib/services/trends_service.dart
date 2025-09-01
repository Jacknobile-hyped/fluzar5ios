import 'dart:convert';
import 'package:http/http.dart' as http;

class TrendData {
  final String keyword;
  final int interest;
  final String platform;
  final DateTime date;
  final bool isRising;
  final double percentageChange;

  TrendData({
    required this.keyword,
    required this.interest,
    required this.platform,
    required this.date,
    required this.isRising,
    required this.percentageChange,
  });

  factory TrendData.fromJson(Map<String, dynamic> json) {
    return TrendData(
      keyword: json['keyword'] ?? '',
      interest: json['interest'] ?? 0,
      platform: json['platform'] ?? '',
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
      isRising: json['isRising'] ?? false,
      percentageChange: (json['percentageChange'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'keyword': keyword,
      'interest': interest,
      'platform': platform,
      'date': date.toIso8601String(),
      'isRising': isRising,
      'percentageChange': percentageChange,
    };
  }
}

class TrendsService {
  static const String _baseUrl = 'https://trend.giuseppemaria162.workers.dev';
  
  // Backup mock data in case the API is unavailable
  static final List<TrendData> _fallbackTrendsData = [
    // TikTok Trends
    TrendData(
      keyword: "Hashtag challenge estate",
      interest: 85,
      platform: "TikTok",
      date: DateTime.now().subtract(Duration(days: 1)),
      isRising: true,
      percentageChange: 78.5,
    ),
    TrendData(
      keyword: "Reel virale TikTok",
      interest: 92,
      platform: "TikTok",
      date: DateTime.now().subtract(Duration(days: 2)),
      isRising: true,
      percentageChange: 45.2,
    ),
    TrendData(
      keyword: "Ballo virale 2025",
      interest: 78,
      platform: "TikTok",
      date: DateTime.now().subtract(Duration(days: 3)),
      isRising: false,
      percentageChange: -12.3,
    ),
    
    // Instagram Trends
    TrendData(
      keyword: "Stories creative",
      interest: 67,
      platform: "Instagram",
      date: DateTime.now().subtract(Duration(days: 1)),
      isRising: true,
      percentageChange: 34.7,
    ),
    TrendData(
      keyword: "Reel Instagram",
      interest: 89,
      platform: "Instagram",
      date: DateTime.now().subtract(Duration(days: 2)),
      isRising: true,
      percentageChange: 56.8,
    ),
    TrendData(
      keyword: "Hashtag moda",
      interest: 45,
      platform: "Instagram",
      date: DateTime.now().subtract(Duration(days: 3)),
      isRising: false,
      percentageChange: -8.9,
    ),
    
    // YouTube Trends
    TrendData(
      keyword: "Shorts virali",
      interest: 73,
      platform: "YouTube",
      date: DateTime.now().subtract(Duration(days: 1)),
      isRising: true,
      percentageChange: 67.2,
    ),
    TrendData(
      keyword: "Tutorial TikTok",
      interest: 58,
      platform: "YouTube",
      date: DateTime.now().subtract(Duration(days: 2)),
      isRising: true,
      percentageChange: 23.4,
    ),
    
    // Facebook Trends
    TrendData(
      keyword: "Post virali Facebook",
      interest: 52,
      platform: "Facebook",
      date: DateTime.now().subtract(Duration(days: 1)),
      isRising: true,
      percentageChange: 28.9,
    ),
    TrendData(
      keyword: "Stories Facebook",
      interest: 41,
      platform: "Facebook",
      date: DateTime.now().subtract(Duration(days: 2)),
      isRising: false,
      percentageChange: -5.2,
    ),
    
    // Twitter/X Trends
    TrendData(
      keyword: "Trend Twitter",
      interest: 42,
      platform: "Twitter",
      date: DateTime.now().subtract(Duration(days: 1)),
      isRising: false,
      percentageChange: -15.6,
    ),
    TrendData(
      keyword: "Hashtag politica",
      interest: 38,
      platform: "Twitter",
      date: DateTime.now().subtract(Duration(days: 2)),
      isRising: true,
      percentageChange: 89.1,
    ),
    
    // Threads Trends
    TrendData(
      keyword: "Thread virali",
      interest: 35,
      platform: "Threads",
      date: DateTime.now().subtract(Duration(days: 1)),
      isRising: true,
      percentageChange: 42.3,
    ),
    TrendData(
      keyword: "Post Threads",
      interest: 29,
      platform: "Threads",
      date: DateTime.now().subtract(Duration(days: 2)),
      isRising: false,
      percentageChange: -8.7,
    ),
  ];

  // Ottiene tutti i trend
  static Future<List<TrendData>> getAllTrends() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/trends'))
          .timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => TrendData.fromJson(json)).toList();
      } else {
        print('API error: ${response.statusCode}');
        return _fallbackTrendsData;
      }
    } catch (e) {
      print('Exception getting trends: $e');
      return _fallbackTrendsData;
    }
  }

  // Ottiene trend per piattaforma specifica
  static Future<List<TrendData>> getTrendsByPlatform(String platform) async {
    final allTrends = await getAllTrends();
    return allTrends.where((trend) => trend.platform == platform).toList();
  }

  // Ottiene trend in crescita
  static Future<List<TrendData>> getRisingTrends() async {
    final allTrends = await getAllTrends();
    return allTrends.where((trend) => trend.isRising).toList();
  }

  // Ottiene trend per gli ultimi N giorni
  static Future<List<TrendData>> getTrendsForLastDays(int days) async {
    final allTrends = await getAllTrends();
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    return allTrends.where((trend) => trend.date.isAfter(cutoffDate)).toList();
  }

  // Ottiene dati per grafico temporale (ultimi 7 giorni)
  static Future<Map<String, List<Map<String, dynamic>>>> getTimeSeriesData() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/time-series'))
          .timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = json.decode(response.body);
        
        final Map<String, List<Map<String, dynamic>>> result = {};
        
        jsonData.forEach((platform, data) {
          if (data is List) {
            result[platform] = (data as List).map((item) {
              return {
                'date': DateTime.parse(item['date']),
                'interest': (item['interest'] ?? 0),
              };
            }).toList();
          }
        });
        
        return result;
      } else {
        print('API error for time series: ${response.statusCode}');
        return _getFallbackTimeSeriesData();
      }
    } catch (e) {
      print('Exception getting time series: $e');
      return _getFallbackTimeSeriesData();
    }
  }

  // Dati di fallback per il grafico temporale
  static Map<String, List<Map<String, dynamic>>> _getFallbackTimeSeriesData() {
    final platforms = ["TikTok", "Instagram", "YouTube", "Twitter", "Facebook", "Threads"];
    final Map<String, List<Map<String, dynamic>>> result = {};
    
    for (String platform in platforms) {
      List<Map<String, dynamic>> platformData = [];
      
      for (int i = 6; i >= 0; i--) {
        final date = DateTime.now().subtract(Duration(days: i));
        final baseInterest = _getBaseInterestForPlatform(platform);
        final randomVariation = (DateTime.now().millisecondsSinceEpoch % 30) - 15;
        
        platformData.add({
          'date': date,
          'interest': (baseInterest + randomVariation).clamp(20, 100),
        });
      }
      
      result[platform] = platformData;
    }
    
    return result;
  }

  static int _getBaseInterestForPlatform(String platform) {
    switch (platform) {
      case "TikTok":
        return 85;
      case "Instagram":
        return 75;
      case "YouTube":
        return 65;
      case "Twitter":
        return 45;
      case "Facebook":
        return 50;
      case "Threads":
        return 35;
      default:
        return 50;
    }
  }

  // Ottiene il trend consigliato (quello con la crescita più forte)
  static Future<TrendData?> getRecommendedTrend() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/recommended'))
          .timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200 && response.body.trim().isNotEmpty && response.body != "null") {
        final json = jsonDecode(response.body);
        return TrendData.fromJson(json);
      } else {
        // Fallback: calcola il trend con crescita migliore
        final risingTrends = await getRisingTrends();
        if (risingTrends.isEmpty) return null;
        
        risingTrends.sort((a, b) => b.percentageChange.compareTo(a.percentageChange));
        return risingTrends.first;
      }
    } catch (e) {
      print('Exception getting recommended trend: $e');
      // Fallback: calcola il trend con crescita migliore
      final risingTrends = await getRisingTrends();
      if (risingTrends.isEmpty) return null;
      
      risingTrends.sort((a, b) => b.percentageChange.compareTo(a.percentageChange));
      return risingTrends.first;
    }
  }

  // Aggiorna i dati manualmente
  static Future<bool> refreshData() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/update'))
          .timeout(Duration(seconds: 15));
      
      return response.statusCode == 200;
    } catch (e) {
      print('Exception refreshing data: $e');
      return false;
    }
  }
} 