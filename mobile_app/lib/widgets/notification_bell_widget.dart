import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart' show NotificationProvider, Notification;

class NotificationBellWidget extends StatefulWidget {
  const NotificationBellWidget({super.key});

  @override
  State<NotificationBellWidget> createState() => _NotificationBellWidgetState();
}

class _NotificationBellWidgetState extends State<NotificationBellWidget> {
  late OverlayEntry _overlayEntry;
  bool _isOverlayShown = false;

  void _showNotificationPanel() {
    if (_isOverlayShown) {
      _overlayEntry.remove();
      _isOverlayShown = false;
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 60,
        right: 16,
        width: 360,
        child: GestureDetector(
          onTap: () {},
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: _NotificationPanel(
              onClose: _hideNotificationPanel,
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry);
    _isOverlayShown = true;
  }

  void _hideNotificationPanel() {
    if (_isOverlayShown) {
      _overlayEntry.remove();
      _isOverlayShown = false;
    }
  }

  @override
  void dispose() {
    if (_isOverlayShown) {
      _overlayEntry.remove();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, notificationProvider, _) {
        final unreadCount = notificationProvider.unreadCount;

        return GestureDetector(
          onTap: _showNotificationPanel,
          child: Semantics(
            label: 'Notifications',
            button: true,
            enabled: true,
            child: Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: _showNotificationPanel,
                  tooltip: 'Notifications',
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      child: Center(
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotificationPanel extends StatefulWidget {
  final VoidCallback onClose;

  const _NotificationPanel({required this.onClose});

  @override
  State<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<_NotificationPanel> {
  @override
  void initState() {
    super.initState();
    _closeOnTapOutside();
  }

  void _closeOnTapOutside() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
      }
    });
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      final tapPosition = event.position;
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final localPosition = renderBox.globalToLocal(tapPosition);
        if (!Offset.zero & renderBox.size.contains(localPosition)) {
          return;
        }
      }
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_handlePointerEvent);
      widget.onClose();
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handlePointerEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, notificationProvider, _) {
        final notifications = notificationProvider.notifications;

        return Container(
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.grey[300]!,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (notifications.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_sweep),
                        onPressed: () {
                          notificationProvider.clearNotifications();
                          widget.onClose();
                        },
                        tooltip: 'Clear all',
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_none,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No notifications',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: notifications.length,
                        itemBuilder: (context, index) {
                          final notification = notifications[index];
                          return _NotificationItem(
                            notification: notification,
                            onTap: () {
                              notificationProvider.markAsRead(notification.id);
                              widget.onClose();
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationItem extends StatelessWidget {
  final Notification notification;
  final VoidCallback onTap;

  const _NotificationItem({
    required this.notification,
    required this.onTap,
  });

  IconData _getIconData(String icon) {
    switch (icon) {
      case 'person_add':
        return Icons.person_add;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'assignment':
        return Icons.assignment;
      case 'assignment_turned_in':
        return Icons.assignment_turned_in;
      case 'inventory_2':
        return Icons.inventory_2;
      case 'payment':
        return Icons.payment;
      case 'check_circle':
        return Icons.check_circle;
      case 'task_alt':
        return Icons.task_alt;
      case 'check':
        return Icons.check;
      case 'schedule':
        return Icons.schedule;
      default:
        return Icons.info;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'success':
        return Colors.green;
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'info':
      default:
        return Colors.blue;
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey[200]!,
            ),
          ),
          color: notification.unread
              ? Colors.blue[50]
              : Colors.transparent,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getIconColor(notification.type).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getIconData(notification.icon),
                color: _getIconColor(notification.type),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: notification.unread
                          ? FontWeight.bold
                          : FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getTimeAgo(notification.timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            if (notification.unread)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
