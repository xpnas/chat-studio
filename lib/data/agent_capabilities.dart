import 'studio_api.dart';

/// Mobile-facing adapters for the management surfaces exposed by the Studio
/// web client.  The wire names intentionally remain unchanged because they
/// are part of the Hermes/Ekko server contract.
extension AgentCapabilitiesApi on StudioApi {
  Future<Map<String, dynamic>> hermesJobs() =>
      request('/api/hermes/jobs', query: {'include_disabled': 'true'});

  Future<Map<String, dynamic>> createHermesJob({
    required String name,
    required String schedule,
    required String prompt,
    String deliver = 'origin',
  }) => request(
    '/api/hermes/jobs',
    method: 'POST',
    body: {
      'name': name,
      'schedule': schedule,
      'prompt': prompt,
      'deliver': deliver,
    },
  );

  Future<Map<String, dynamic>> updateHermesJob(
    String id,
    Map<String, dynamic> values,
  ) => request(
    '/api/hermes/jobs/${Uri.encodeComponent(id)}',
    method: 'PATCH',
    body: values,
  );

  Future<void> deleteHermesJob(String id) async {
    await request(
      '/api/hermes/jobs/${Uri.encodeComponent(id)}',
      method: 'DELETE',
    );
  }

  Future<Map<String, dynamic>> runHermesJob(String id) => request(
    '/api/hermes/jobs/${Uri.encodeComponent(id)}/run',
    method: 'POST',
  );

  Future<Map<String, dynamic>> pauseHermesJob(String id) => request(
    '/api/hermes/jobs/${Uri.encodeComponent(id)}/pause',
    method: 'POST',
  );

  Future<Map<String, dynamic>> resumeHermesJob(String id) => request(
    '/api/hermes/jobs/${Uri.encodeComponent(id)}/resume',
    method: 'POST',
  );

  Future<Map<String, dynamic>> hermesSkills() =>
      request('/api/hermes/skills', query: {'profile': profile});

  Future<String> hermesSkillContent(String category, String name) async {
    final value = (await request(
      '/api/hermes/skills/${Uri.encodeComponent(category)}/${Uri.encodeComponent(name)}/SKILL.md',
    ))['content'];
    return value is String ? value : '';
  }

  Future<void> updateHermesSkill(
    String category,
    String name,
    String content,
  ) async {
    await request(
      '/api/hermes/skills/${Uri.encodeComponent(category)}/${Uri.encodeComponent(name)}',
      method: 'PUT',
      body: {'content': content},
    );
  }

  Future<void> deleteHermesSkill(String category, String name) async {
    await request(
      '/api/hermes/skills/${Uri.encodeComponent(category)}/${Uri.encodeComponent(name)}',
      method: 'DELETE',
    );
  }

  Future<void> setHermesSkillEnabled(String name, bool enabled) async {
    await request(
      '/api/hermes/skills/toggle',
      method: 'PUT',
      body: {'name': name, 'enabled': enabled},
    );
  }

  Future<void> setHermesSkillPinned(String name, bool pinned) async {
    await request(
      '/api/hermes/skills/pin',
      method: 'PUT',
      body: {'name': name, 'pinned': pinned},
    );
  }

  Future<Map<String, dynamic>> hermesPlugins() =>
      request('/api/hermes/plugins');

  Future<void> setHermesPluginEnabled(String key, bool enabled) async {
    await request(
      '/api/hermes/plugins/${Uri.encodeComponent(key)}/${enabled ? 'enable' : 'disable'}',
      method: 'POST',
    );
  }

  Future<Map<String, dynamic>> hermesMcpServers() =>
      request('/api/hermes/mcp/servers');

  Future<Map<String, dynamic>> hermesMcpTest(String name) => request(
    '/api/hermes/mcp/servers/${Uri.encodeComponent(name)}/test',
    method: 'POST',
  );

  Future<Map<String, dynamic>> updateHermesMcp(
    String name,
    Map<String, dynamic> config,
  ) => request(
    '/api/hermes/mcp/servers/${Uri.encodeComponent(name)}',
    method: 'PATCH',
    body: {'config': config},
  );

  Future<Map<String, dynamic>> hermesMcpReload([String? name]) => request(
    '/api/hermes/mcp/reload',
    method: 'POST',
    query: {if (name != null && name.isNotEmpty) 'server': name},
  );

  Future<Map<String, dynamic>> addHermesMcp(
    String name,
    Map<String, dynamic> config,
  ) => request(
    '/api/hermes/mcp/servers',
    method: 'POST',
    body: {'name': name, 'config': config},
  );

  Future<void> deleteHermesMcp(String name) async {
    await request(
      '/api/hermes/mcp/servers/${Uri.encodeComponent(name)}',
      method: 'DELETE',
    );
  }

  Future<Map<String, dynamic>> hermesMemory() => request('/api/hermes/memory');

  Future<void> saveHermesMemory(String section, String content) async {
    await request(
      '/api/hermes/memory',
      method: 'POST',
      body: {'section': section, 'content': content},
    );
  }

  Future<Map<String, dynamic>> ekkoSkills({String query = ''}) => request(
    '/api/ekko/skills',
    query: {if (query.isNotEmpty) 'query': query},
  );

  Future<Map<String, dynamic>> ekkoSkill(String name) =>
      request('/api/ekko/skills/${Uri.encodeComponent(name)}');

  Future<Map<String, dynamic>> createEkkoSkill(
    String name,
    String content, {
    String category = 'misc',
  }) => request(
    '/api/ekko/skills',
    method: 'POST',
    body: {'name': name, 'content': content, 'category': category},
  );

  Future<void> deleteEkkoSkill(String name) async {
    await request(
      '/api/ekko/skills/${Uri.encodeComponent(name)}',
      method: 'DELETE',
    );
  }

  Future<Map<String, dynamic>> updateEkkoSkill(String name, String content) =>
      request(
        '/api/ekko/skills/${Uri.encodeComponent(name)}',
        method: 'PUT',
        body: {'content': content},
      );

  Future<void> setEkkoSkillEnabled(String name, bool enabled) async {
    await request(
      '/api/ekko/skills/${Uri.encodeComponent(name)}/toggle',
      method: 'PUT',
      body: {'enabled': enabled},
    );
  }

  Future<Map<String, dynamic>> ekkoMemory({
    String query = '',
    String? status,
  }) => request(
    '/api/ekko/memory',
    query: {
      if (query.isNotEmpty) 'query': query,
      if (status != null && status.isNotEmpty) 'status': status,
    },
  );

  Future<Map<String, dynamic>> updateEkkoMemory(
    String id,
    int expectedRevision,
    String title,
    String content,
    List<String> tags,
  ) => request(
    '/api/ekko/memory/${Uri.encodeComponent(id)}',
    method: 'PATCH',
    body: {
      'expectedRevision': expectedRevision,
      'title': title,
      'content': content,
      'tags': tags,
    },
  );

  Future<void> deleteEkkoMemory(String id, int expectedRevision) async {
    await request(
      '/api/ekko/memory/${Uri.encodeComponent(id)}',
      method: 'DELETE',
      body: {'expectedRevision': expectedRevision},
    );
  }

  Future<Map<String, dynamic>> ekkoMcpServers() =>
      request('/api/ekko/mcp/servers');

  Future<Map<String, dynamic>> addEkkoMcp(
    String name,
    Map<String, dynamic> config,
  ) => request(
    '/api/ekko/mcp/servers',
    method: 'POST',
    body: {'name': name, 'config': config},
  );

  Future<Map<String, dynamic>> updateEkkoMcp(
    String name,
    Map<String, dynamic> config,
  ) => request(
    '/api/ekko/mcp/servers/${Uri.encodeComponent(name)}',
    method: 'PATCH',
    body: {'config': config},
  );

  Future<Map<String, dynamic>> testEkkoMcp(String name) => request(
    '/api/ekko/mcp/servers/${Uri.encodeComponent(name)}/test',
    method: 'POST',
  );

  Future<void> deleteEkkoMcp(String name) async {
    await request(
      '/api/ekko/mcp/servers/${Uri.encodeComponent(name)}',
      method: 'DELETE',
    );
  }
}
