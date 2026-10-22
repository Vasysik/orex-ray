import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'orex_notice.dart';

/// Common clipboard and interface-selection policy for proxy links.
///
/// 0.0.0.0 is a bind address, never a usable client URL. The localhost URL
/// is always offered; LAN IPv4 URLs are only offered when LAN is enabled.
class OrexProxyCopy {
  const OrexProxyCopy._();

  static Future<void> copy(
    BuildContext context, {
    required String protocol,
    required String address,
  }) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!context.mounted) return;
    if (Scaffold.maybeOf(context) != null) {
      OrexNotice.copied(context, '$protocol: адрес скопирован');
    }
  }

  static Future<void> showAddressMenu(
    BuildContext context, {
    required Offset globalPosition,
    required String protocol,
    required String scheme,
    required int port,
    required bool allowLan,
  }) async {
    final localhost = '$scheme://127.0.0.1:$port';
    final networkAddresses = <({String address, String interfaceName})>[];
    if (allowLan && !kIsWeb) {
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
          includeLinkLocal: false,
        );
        final seen = <String>{};
        for (final adapter in interfaces) {
          for (final ip in adapter.addresses) {
            if (_isPrivateIpv4(ip.address) && seen.add(ip.address)) {
              networkAddresses.add(
                (address: ip.address, interfaceName: adapter.name),
              );
            }
          }
        }
      } on SocketException {
        // Some platforms or sandbox policies forbid interface enumeration.
      } on UnsupportedError {
        // Localhost is still available on unsupported platforms.
      }
    }
    if (!context.mounted) return;

    final overlayState = Overlay.of(context);
    if (!overlayState.mounted) return;
    final overlay = overlayState.context.findRenderObject() as RenderBox;
    final point = overlay.globalToLocal(globalPosition);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        point.dx,
        point.dy,
        overlay.size.width - point.dx,
        overlay.size.height - point.dy,
      ),
      items: [
        PopupMenuItem(
          value: localhost,
          child: const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.computer_rounded),
            title: Text('127.0.0.1 · это устройство'),
          ),
        ),
        if (!allowLan)
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('Доступ из локальной сети запрещён'),
          )
        else if (networkAddresses.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('IPv4-адрес локальной сети не найден'),
          )
        else
          for (final item in networkAddresses)
            PopupMenuItem(
              value: '$scheme://${item.address}:$port',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lan_rounded),
                title: Text(item.address),
                subtitle: Text(
                  item.interfaceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
      ],
    );
    if (selected != null && context.mounted) {
      await copy(context, protocol: protocol, address: selected);
    }
  }
}

bool _isPrivateIpv4(String address) {
  final octets = address.split('.').map(int.tryParse).toList();
  if (octets.length != 4 || octets.any((v) => v == null || v < 0 || v > 255)) {
    return false;
  }
  final a = octets[0]!;
  final b = octets[1]!;
  return a == 10 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 100 && b >= 64 && b <= 127);
}
