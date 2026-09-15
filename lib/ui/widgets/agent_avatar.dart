import 'dart:typed_data';
import '../../data/agent_catalog.dart';
import '../../data/studio_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../state/app_controller.dart';
import '../theme.dart';

/// Matches the pinned Studio Agent Manager. Images are loaded from the user's
/// server, not redistributed or fetched from an unrelated third-party host.
class AgentIdentity {
  const AgentIdentity(this.name, this.file);
  final String name;
  final String? file;
  static AgentIdentity resolve(String id) {
    final meta = AgentChoice.metadata(
      id.isEmpty ? StudioProtocol.builtInAgentId : id,
    );
    return AgentIdentity(meta.name, meta.icon);
  }

  static AgentIdentity current(AppController? c) =>
      resolve(c?.current?.agent ?? c?.engine ?? '');
}

class AgentAvatar extends StatelessWidget {
  const AgentAvatar({
    super.key,
    required this.controller,
    this.size = 22,
    this.agentId,
  });
  final AppController? controller;
  final double size;
  final String? agentId;
  @override
  Widget build(BuildContext context) {
    final identity = agentId == null
        ? AgentIdentity.current(controller)
        : AgentIdentity.resolve(agentId!);

    final fallback = identity.name == StudioProtocol.builtInAgentName
        ? ChatStudioMark(size: size, label: StudioProtocol.builtInAgentName)
        : Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(size * .25),
            ),
            child: Text(
              identity.name.characters.take(2).toString(),
              style: TextStyle(
                fontSize: size * .45,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
    final api = controller?.api;
    final file = identity.file;
    return Semantics(
      label: '${identity.name} Agent',
      image: true,
      child: Tooltip(
        message: identity.name,
        child: SizedBox.square(
          dimension: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * .2),
            child: file == null || api == null
                ? fallback
                : FutureBuilder<Uint8List?>(
                    key: ValueKey('${api.address.value}:$file'),
                    future: api.agentIcon(file),
                    builder: (_, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes == null) return fallback;
                      return file.endsWith('.svg')
                          ? SvgPicture.memory(
                              bytes,
                              width: size,
                              height: size,
                              errorBuilder: (_, _, _) => fallback,
                            )
                          : Image.memory(
                              bytes,
                              width: size,
                              height: size,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => fallback,
                            );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
