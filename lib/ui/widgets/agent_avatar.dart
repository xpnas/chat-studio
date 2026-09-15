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
  static AgentIdentity resolve(String id) => switch (id.trim().toLowerCase()) {
    '' ||
    'ekko' ||
    'ekko_agent' ||
    'ekko-agent' => const AgentIdentity('Ekko', 'ekko-agent.png'),
    'hermes' => const AgentIdentity('Hermes', 'hermes.png'),
    'codex' => const AgentIdentity('Codex', 'codex-openai.png'),
    'claude' ||
    'claude-code' => const AgentIdentity('Claude', 'claude-code.svg'),
    'pi' => const AgentIdentity('Pi', 'pi.svg'),
    'grok' => const AgentIdentity('Grok', 'grok.svg'),
    'opencode' => const AgentIdentity('OpenCode', 'opencode.png'),
    _ => AgentIdentity(id.trim(), null),
  };
  static AgentIdentity current(AppController? c) =>
      resolve(c?.current?.agent ?? c?.engine ?? '');
}

class AgentAvatar extends StatelessWidget {
  const AgentAvatar({super.key, required this.controller, this.size = 22});
  final AppController? controller;
  final double size;
  @override
  Widget build(BuildContext context) {
    final identity = AgentIdentity.current(controller);
    final origin = controller?.api?.address.uri;
    final fallback = identity.name == 'Ekko'
        ? EkkoMark(size: size, label: 'Ekko')
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
    final url = origin?.resolve('/coding-agents/${identity.file}').toString();
    return Semantics(
      label: '${identity.name} Agent',
      image: true,
      child: Tooltip(
        message: identity.name,
        child: SizedBox.square(
          dimension: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * .2),
            child: identity.file == null || url == null
                ? fallback
                : identity.file!.endsWith('.svg')
                ? SvgPicture.network(
                    url,
                    key: ValueKey(url),
                    width: size,
                    height: size,
                    placeholderBuilder: (_) => fallback,
                    errorBuilder: (_, _, _) => fallback,
                  )
                : Image.network(
                    url,
                    key: ValueKey(url),
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => fallback,
                    loadingBuilder: (_, child, loading) =>
                        loading == null ? child : fallback,
                  ),
          ),
        ),
      ),
    );
  }
}
