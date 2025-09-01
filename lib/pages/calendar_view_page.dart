import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import './scheduled_post_details_page.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:async';

class CalendarViewPage extends StatefulWidget {
  final List<Map<String, dynamic>> scheduledPosts;

  const CalendarViewPage({
    Key? key,
    required this.scheduledPosts,
  }) : super(key: key);

  @override
  State<CalendarViewPage> createState() => _CalendarViewPageState();
}

class _CalendarViewPageState extends State<CalendarViewPage> with WidgetsBindingObserver {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late CalendarFormat _calendarFormat;
  late Map<DateTime, List<Map<String, dynamic>>> _events;
  bool _isTimelineView = false;
  bool _isYearView = false;
  bool _isWeekView = false;
  bool _showLegend = false;
  Timer? _refreshTimer;

  // Mapping platform names to their logo assets
  final Map<String, String> _platformLogos = {
    'TikTok': 'assets/loghi/logo_tiktok.png',
    'YouTube': 'assets/loghi/logo_yt.png',
    'Instagram': 'assets/loghi/logo_insta.png',
    'Facebook': 'assets/loghi/logo_facebook.png',
    'Twitter': 'assets/loghi/logo_twitter.png',
    'Threads': 'assets/loghi/threads_logo.png',
  };

  final Map<String, IconData> _platformIcons = {
    'TikTok': Icons.music_note,
    'YouTube': Icons.play_arrow,
    'Instagram': Icons.camera_alt,
    'Facebook': Icons.facebook,
    'Twitter': Icons.chat,
    'Threads': Icons.chat_bubble_outline,
    'Snapchat': Icons.photo_camera,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _calendarFormat = CalendarFormat.month;
    _events = _groupEventsByDay(widget.scheduledPosts);

    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() {
          _events = _groupEventsByDay(widget.scheduledPosts);
        });
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(CalendarViewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scheduledPosts != oldWidget.scheduledPosts) {
      setState(() {
        _events = _groupEventsByDay(widget.scheduledPosts);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _events = _groupEventsByDay(widget.scheduledPosts);
      });
    }
  }

  Map<DateTime, List<Map<String, dynamic>>> _groupEventsByDay(List<Map<String, dynamic>> posts) {
    Map<DateTime, List<Map<String, dynamic>>> eventsByDay = {};

    for (final post in posts) {
      final scheduledTime = post['scheduledTime'] as int?;
      if (scheduledTime != null) {
        final dateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
        final dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);
        
        if (eventsByDay[dateOnly] == null) {
          eventsByDay[dateOnly] = [];
        }
        eventsByDay[dateOnly]!.add(post);
      }
    }

    print('Grouped events: ${eventsByDay.length} days with events');
    return eventsByDay;
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    return _events[dateOnly] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Calendar View',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(_showLegend ? Icons.info : Icons.info_outline),
            tooltip: 'Platform Legend',
            onPressed: () {
              setState(() {
                _showLegend = !_showLegend;
              });
            },
          ),
          IconButton(
            icon: Icon(_isYearView ? Icons.calendar_month : Icons.calendar_view_month),
            tooltip: _isYearView ? 'Month View' : 'Year View',
            onPressed: () {
              setState(() {
                _isYearView = !_isYearView;
                if (!_isYearView) {
                  _isTimelineView = false;
                  _isWeekView = false;
                }
              });
            },
          ),
          if (!_isYearView && !_isTimelineView)
            IconButton(
              icon: Icon(_isWeekView ? Icons.view_week_outlined : Icons.view_week),
              tooltip: _isWeekView ? 'Month View' : 'Week View',
              onPressed: () {
                setState(() {
                  _isWeekView = !_isWeekView;
                });
              },
            ),
          if (!_isYearView && !_isWeekView)
            IconButton(
              icon: Icon(_isTimelineView ? Icons.calendar_month : Icons.view_timeline),
              tooltip: _isTimelineView ? 'Calendar View' : 'Timeline View',
              onPressed: () {
                setState(() {
                  _isTimelineView = !_isTimelineView;
                });
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_showLegend) _buildLegendOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isYearView) {
      return _buildYearView();
    } else if (_isTimelineView) {
      return _buildTimelineView();
    } else if (_isWeekView) {
      return _buildWeekView();
    } else {
      return _buildCalendarView();
    }
  }

  Widget _buildCalendarView() {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final firstDay = now.subtract(const Duration(days: 365));
    final lastDay = now.add(const Duration(days: 365));
    
    return Column(
      children: [
        // Elegant header with shadow
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _focusedDay = DateTime.now();
                    _selectedDay = DateTime.now();
                  });
                },
                icon: Icon(Icons.today, size: 18),
                label: Text('Today'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Text(
                DateFormat('MMMM yyyy').format(_focusedDay),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_left),
                    onPressed: () {
                      setState(() {
                        _focusedDay = DateTime(
                          _focusedDay.year,
                          _focusedDay.month - 1,
                          _focusedDay.day,
                        );
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_right),
                    onPressed: () {
                      setState(() {
                        _focusedDay = DateTime(
                          _focusedDay.year,
                          _focusedDay.month + 1,
                          _focusedDay.day,
                        );
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // More professional calendar styling
        TableCalendar(
          firstDay: firstDay,
          lastDay: lastDay,
          focusedDay: _focusedDay,
          calendarFormat: _calendarFormat,
          selectedDayPredicate: (day) {
            return isSameDay(_selectedDay, day);
          },
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          onFormatChanged: (format) {
            setState(() {
              _calendarFormat = format;
            });
          },
          onPageChanged: (focusedDay) {
            setState(() {
              _focusedDay = focusedDay;
            });
          },
          eventLoader: _getEventsForDay,
          calendarStyle: CalendarStyle(
            // Today styling
            todayDecoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
            
            // Selected day styling
            selectedDecoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
            
            // Weekend styling
            weekendTextStyle: TextStyle(
              color: theme.colorScheme.primary.withOpacity(0.8),
            ),
            
            // Markers (event indicators)
            markersMaxCount: 4,
            markerDecoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              shape: BoxShape.circle,
            ),
            markerSize: 7,
            markerMargin: const EdgeInsets.symmetric(horizontal: 1),
            
            // Outside days styling (days from other months)
            outsideTextStyle: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
            outsideDecoration: const BoxDecoration(shape: BoxShape.circle),
            
            // Default day cell styling
            defaultDecoration: const BoxDecoration(shape: BoxShape.circle),
            defaultTextStyle: TextStyle(color: theme.colorScheme.onSurface),
            
            // Cell margins for more spacious look
            cellMargin: const EdgeInsets.all(4),
          ),
          headerVisible: false,
          
          // Day of week (header) styling
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            weekendStyle: TextStyle(
              color: theme.colorScheme.primary.withOpacity(0.8),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
          ),
          
          // Calendar format and style
          availableCalendarFormats: const {
            CalendarFormat.month: 'Month',
            CalendarFormat.twoWeeks: '2 Weeks',
            CalendarFormat.week: 'Week',
          },
        ),
        
        Divider(height: 1),
        
        // Tab or indicator to show selected date
        Container(
          color: theme.colorScheme.surface,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  DateFormat('EEE, MMM d').format(_selectedDay),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Events',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${_getEventsForDay(_selectedDay).length} posts',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: _buildEventsList(),
        ),
      ],
    );
  }

  Widget _buildTimelineView() {
    final theme = Theme.of(context);
    final eventDays = _events.keys.toList()..sort();
    
    if (eventDays.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No scheduled posts found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: eventDays.length,
      itemBuilder: (context, index) {
        final day = eventDays[index];
        final dayEvents = _events[day]!;
        final isToday = isSameDay(day, DateTime.now());
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isToday 
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    DateFormat('EEE, MMM d').format(day),
                    style: TextStyle(
                      color: isToday 
                          ? theme.colorScheme.onPrimary 
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${dayEvents.length} ${dayEvents.length == 1 ? 'post' : 'posts'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
            
            if (index < eventDays.length - 1) 
              Container(
                margin: const EdgeInsets.only(left: 16),
                width: 2,
                height: 100,
                color: theme.colorScheme.primary.withOpacity(0.3),
              ),
              
            Padding(
              padding: const EdgeInsets.only(left: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: dayEvents.map((post) {
                  final scheduledTime = post['scheduledTime'] as int?;
                  final DateTime dateTime = scheduledTime != null
                      ? DateTime.fromMillisecondsSinceEpoch(scheduledTime)
                      : DateTime.now();
                  final timeString = DateFormat('HH:mm').format(dateTime);
                  
                  // Safely extract platforms list for timeline view items
                  List<String> platforms = [];
                  if (post['platforms'] != null) {
                    if (post['platforms'] is List) {
                      platforms = (post['platforms'] as List)
                          .map((e) => e.toString())
                          .toList();
                    }
                  }
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16, top: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ScheduledPostDetailsPage(
                              post: post,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        timeString,
                                        style: TextStyle(
                                          color: theme.colorScheme.onPrimary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (platforms.isNotEmpty)
                                      _buildPlatformIcons(platforms),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _buildPostThumbnail(post, theme),
                                ),
                                const SizedBox(width: 16),
                                
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (post['title'] != null && post['title'].toString().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8.0),
                                          child: Text(
                                            post['title'],
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      Text(
                                        post['description'] ?? 'No description',
                                        style: theme.textTheme.bodyMedium,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ScheduledPostDetailsPage(
                                          post: post,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text('View Details'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEventsList() {
    final theme = Theme.of(context);
    final events = _getEventsForDay(_selectedDay);
    
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No posts scheduled for this day',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Selected date: ${DateFormat('yyyy-MM-dd').format(_selectedDay)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: events.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final post = events[index];
        final scheduledTime = post['scheduledTime'] as int?;
        final DateTime dateTime = scheduledTime != null
            ? DateTime.fromMillisecondsSinceEpoch(scheduledTime)
            : DateTime.now();
        final timeString = DateFormat('HH:mm').format(dateTime);
        
        // Safely extract platforms list
        List<String> platforms = [];
        if (post['platforms'] != null) {
          if (post['platforms'] is List) {
            platforms = (post['platforms'] as List)
                .map((e) => e.toString())
                .toList();
          }
        }
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ScheduledPostDetailsPage(
                    post: post,
                  ),
                ),
              ).then((_) {
                // Refresh events when returning from details page
                if (mounted) {
                  setState(() {
                    _events = _groupEventsByDay(widget.scheduledPosts);
                  });
                }
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              timeString,
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (platforms.isNotEmpty)
                            _buildPlatformIcons(platforms),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.more_vert),
                        onPressed: () {
                          _showPostOptions(post);
                        },
                      ),
                    ],
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildPostThumbnail(post, theme),
                      ),
                      const SizedBox(width: 16),
                      
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (post['title'] != null && post['title'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Text(
                                  post['title'],
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            Text(
                              post['description'] ?? 'No description',
                              style: theme.textTheme.bodyMedium,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ScheduledPostDetailsPage(
                                post: post,
                              ),
                            ),
                          ).then((_) {
                            if (mounted) {
                              setState(() {
                                _events = _groupEventsByDay(widget.scheduledPosts);
                              });
                            }
                          });
                        },
                        child: Text('View Details'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPostOptions(Map<String, dynamic> post) {
    final theme = Theme.of(context);
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.visibility, color: theme.colorScheme.primary),
                title: Text('View Details'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ScheduledPostDetailsPage(
                        post: post,
                      ),
                    ),
                  ).then((_) {
                    if (mounted) {
                      setState(() {
                        _events = _groupEventsByDay(widget.scheduledPosts);
                      });
                    }
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPostThumbnail(Map<String, dynamic> post, ThemeData theme) {
    final videoPath = post['video_path'] as String?;
    final thumbnailPath = post['thumbnail_path'] as String?;
    
    try {
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        final file = File(thumbnailPath);
        if (file.existsSync()) {
          return SizedBox(
            width: 100,
            height: 75,
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                print('Error loading thumbnail: $error');
                return _buildDefaultThumbnail(theme);
              },
            ),
          );
        } else {
          return _buildDefaultThumbnail(theme);
        }
      } else if (videoPath != null && videoPath.isNotEmpty) {
        return SizedBox(
          width: 100,
          height: 75,
          child: Stack(
            children: [
              Container(
                color: theme.colorScheme.surfaceVariant,
              ),
              Center(
                child: Icon(
                  Icons.play_circle_fill,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      } else {
        return _buildDefaultThumbnail(theme);
      }
    } catch (e) {
      print('Error in _buildPostThumbnail: $e');
      return _buildDefaultThumbnail(theme);
    }
  }

  Widget _buildDefaultThumbnail(ThemeData theme) {
    return Container(
      width: 100,
      height: 75,
      color: theme.colorScheme.surfaceVariant,
      child: Center(
        child: Icon(
          Icons.image,
          size: 36,
          color: theme.colorScheme.primary.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildPlatformIcons(List<String> platforms) {
    if (platforms.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Limit to showing max 3 platforms with a +N indicator if there are more
    final displayCount = platforms.length > 3 ? 3 : platforms.length;
    final displayPlatforms = platforms.take(displayCount).toList();
    
    return Row(
      children: [
        ...displayPlatforms.map((platform) {
          // Use platform logo if available, otherwise use fallback icon
          final logoPath = _platformLogos[platform];
          
          if (logoPath != null) {
            return Container(
              margin: const EdgeInsets.only(right: 4),
              width: 24,
              height: 24,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  logoPath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback to icon if image fails to load
                    return Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _platformIcons[platform] ?? Icons.public,
                        size: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    );
                  },
                ),
              ),
            );
          } else {
            // Fallback to icon
            return Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _platformIcons[platform] ?? Icons.public,
                size: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            );
          }
        }).toList(),
        
        // Show +N indicator if there are more platforms
        if (platforms.length > 3)
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '+${platforms.length - 3}',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildYearView() {
    final theme = Theme.of(context);
    
    final int currentYear = _focusedDay.year;
    final int currentMonth = DateTime.now().month;
    final int currentDay = DateTime.now().day;
    
    final List<DateTime> monthsInYear = List.generate(12, (index) {
      return DateTime(currentYear, index + 1, 1);
    });
    
    return Column(
      children: [
        // Elegant year selector header with shadow
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(
                  Icons.chevron_left,
                  color: theme.colorScheme.primary,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.primary,
                ),
                onPressed: () {
                  setState(() {
                    _focusedDay = DateTime(currentYear - 1, _focusedDay.month, 1);
                  });
                },
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  currentYear.toString(),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.primary,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.primary,
                ),
                onPressed: () {
                  setState(() {
                    _focusedDay = DateTime(currentYear + 1, _focusedDay.month, 1);
                  });
                },
              ),
            ],
          ),
        ),
        
        // Month grid with enhanced styling
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: monthsInYear.length,
            itemBuilder: (context, index) {
              final month = monthsInYear[index];
              final monthName = DateFormat('MMMM').format(month);
              final monthNameShort = DateFormat('MMM').format(month);
              
              // Count posts in this month
              int postCount = 0;
              _events.forEach((date, posts) {
                if (date.year == month.year && date.month == month.month) {
                  postCount += posts.length;
                }
              });
              
              final bool isCurrentMonth = DateTime.now().year == month.year && 
                                          DateTime.now().month == month.month;
              
              return InkWell(
                onTap: () {
                  setState(() {
                    _focusedDay = month;
                    _selectedDay = month;
                    _isYearView = false;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: isCurrentMonth 
                        ? LinearGradient(
                            colors: [
                              theme.colorScheme.primary.withOpacity(0.8),
                              theme.colorScheme.primary.withOpacity(0.4),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ) 
                        : null,
                    color: isCurrentMonth 
                        ? null
                        : theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: isCurrentMonth 
                        ? [
                            BoxShadow(
                              color: theme.colorScheme.primary.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ] 
                        : null,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Month name
                      Text(
                        monthNameShort,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: isCurrentMonth ? FontWeight.bold : FontWeight.normal,
                          color: isCurrentMonth 
                              ? Colors.white
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Post count
                      if (postCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrentMonth 
                                ? Colors.white.withOpacity(0.3)
                                : theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$postCount ${postCount == 1 ? 'post' : 'posts'}',
                            style: TextStyle(
                              color: isCurrentMonth 
                                  ? Colors.white
                                  : theme.colorScheme.onPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Text(
                          'No posts',
                          style: TextStyle(
                            color: isCurrentMonth 
                                ? Colors.white.withOpacity(0.8)
                                : theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeekView() {
    final theme = Theme.of(context);
    
    final DateTime startOfWeek = _focusedDay.subtract(
      Duration(days: _focusedDay.weekday - 1),
    );
    
    final List<DateTime> daysInWeek = List.generate(7, (index) {
      return startOfWeek.add(Duration(days: index));
    });
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _focusedDay = DateTime.now();
                    _selectedDay = DateTime.now();
                  });
                },
                icon: Icon(Icons.today),
                label: Text('Today'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
              ),
              Text(
                'Week of ${DateFormat('MMM d').format(startOfWeek)}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left),
                    onPressed: () {
                      setState(() {
                        _focusedDay = _focusedDay.subtract(const Duration(days: 7));
                        _selectedDay = _focusedDay;
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right),
                    onPressed: () {
                      setState(() {
                        _focusedDay = _focusedDay.add(const Duration(days: 7));
                        _selectedDay = _focusedDay;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: daysInWeek.map((day) {
              final dayName = DateFormat('E').format(day);
              final isToday = isSameDay(day, DateTime.now());
              final isSelected = isSameDay(day, _selectedDay);
              
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDay = day;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected 
                              ? theme.colorScheme.primary
                              : theme.dividerColor,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          dayName,
                          style: TextStyle(
                            fontWeight: isToday || isSelected 
                                ? FontWeight.bold 
                                : FontWeight.normal,
                            color: isToday 
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          day.day.toString(),
                          style: TextStyle(
                            fontWeight: isToday || isSelected 
                                ? FontWeight.bold 
                                : FontWeight.normal,
                            fontSize: 16,
                            color: isToday 
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (_events[DateTime(day.year, day.month, day.day)]?.isNotEmpty ?? false)
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        
        const SizedBox(height: 16),
        
        Expanded(
          child: _buildEventsList(),
        ),
      ],
    );
  }

  Widget _buildLegendOverlay() {
    final theme = Theme.of(context);
    
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Platform Legend',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _showLegend = false;
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _platformIcons.entries.map((entry) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Image.asset(
                            _platformLogos[entry.key] ?? '',
                            width: 16,
                            height: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          entry.key,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Divider(),
                const SizedBox(height: 8),
                Text(
                  'Color Indicators:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Post scheduled for this day'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Today'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 