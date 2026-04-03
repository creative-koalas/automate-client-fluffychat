import 'package:psygo/core/api_client.dart';

import '../models/invite_candidate.dart';

class InviteCandidateRepository {
  final PsygoApiClient _apiClient;

  InviteCandidateRepository({PsygoApiClient? apiClient})
      : _apiClient = apiClient ?? PsygoApiClient();

  Future<List<InviteCandidate>> searchInviteCandidates({
    required String query,
    int limit = 20,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/invite-candidates/search',
      queryParameters: <String, String>{
        'query': query,
        'limit': limit.toString(),
      },
      fromJsonT: (data) => data as Map<String, dynamic>,
    );

    final data = response.data;
    if (data == null) {
      return const <InviteCandidate>[];
    }

    final rawItems = data['items'];
    if (rawItems is! List) {
      return const <InviteCandidate>[];
    }

    return rawItems
        .whereType<Map>()
        .map(
          (raw) => InviteCandidate.fromJson(
            raw.cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

  void dispose() {
    _apiClient.dispose();
  }
}
