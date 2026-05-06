import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/enums.dart';
import '../../../models/session.dart';
import '../../auth/providers/auth_providers.dart';

/// Mock dashboard sessions for beta 0.2.
///
/// TODO: replace with real Firestore stream when session_service is implemented.
/// Until then, this generates 6 in-memory sessions on demand.
///
/// One session is "owned" by the current logged-in user (myStatus = host) so
/// the demo shows the full range of join statuses. The remaining 5 are
/// hardcoded with varied statuses (notJoined, joined, pending).
List<Session> _generateMockSessions(String currentUserId) {
  final now = DateTime.now();

  return [
    // 1. Public, not joined yet — typical "discover" card
    Session(
      id: 'mock-1',
      title: 'CS101 Final Exam Prep',
      subject: Subject.computerScience,
      description:
          'Preparing for the final exam covering algorithms, data structures, and complexity theory.',
      visibility: SessionVisibility.public,
      hostId: 'mock-host-1',
      hostName: 'Alex Johnson',
      hostPhotoUrl: null,
      startTime: DateTime(now.year, now.month, now.day + 2, 14, 0),
      endTime: DateTime(now.year, now.month, now.day + 2, 17, 0),
      location: 'Library Room 203',
      capacity: 8,
      participantCount: 5,
      hashtags: const ['algorithms', 'cs101', 'exam'],
      myStatus: JoinStatus.notJoined,
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now.subtract(const Duration(days: 3)),
    ),

    // 2. Approval visibility — has to request to join
    Session(
      id: 'mock-2',
      title: 'Calculus II Study Group',
      subject: Subject.mathematics,
      description:
          'Working through integration techniques and series convergence. Bring your practice sets!',
      visibility: SessionVisibility.approval,
      joinApproval: JoinApproval.hostApproval,
      hostId: 'mock-host-2',
      hostName: 'Priya Sharma',
      hostPhotoUrl: null,
      startTime: DateTime(now.year, now.month, now.day + 1, 10, 0),
      endTime: DateTime(now.year, now.month, now.day + 1, 12, 0),
      location: 'Engineering Block B, Room 101',
      capacity: 6,
      participantCount: 2,
      hashtags: const ['calculus', 'math', 'integration'],
      myStatus: JoinStatus.notJoined,
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(days: 2)),
    ),

    // 3. Private (password-protected) — not joined
    Session(
      id: 'mock-3',
      title: 'Quantum Mechanics Deep Dive',
      subject: Subject.physics,
      description:
          'Private session covering wave functions and Schrödinger equation. Password required.',
      visibility: SessionVisibility.private,
      hostId: 'mock-host-3',
      hostName: 'Dr. Tanaka',
      hostPhotoUrl: null,
      startTime: DateTime(now.year, now.month, now.day + 3, 15, 30),
      endTime: DateTime(now.year, now.month, now.day + 3, 17, 30),
      location: 'Physics Lab 4',
      capacity: 5,
      participantCount: 3,
      hashtags: const ['quantum', 'physics'],
      passwordHash: 'mock-hash',
      myStatus: JoinStatus.notJoined,
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    ),

    // 4. Already joined — "Joined" badge
    Session(
      id: 'mock-4',
      title: 'Organic Chemistry Review',
      subject: Subject.chemistry,
      description: 'Reviewing reaction mechanisms and functional groups.',
      visibility: SessionVisibility.public,
      hostId: 'mock-host-4',
      hostName: 'Sara Müller',
      hostPhotoUrl: null,
      startTime: DateTime(now.year, now.month, now.day + 4, 13, 0),
      endTime: DateTime(now.year, now.month, now.day + 4, 15, 0),
      location: 'Science Building 2F',
      capacity: 10,
      participantCount: 7,
      hashtags: const ['chemistry', 'organic', 'review'],
      myStatus: JoinStatus.joined,
      createdAt: now.subtract(const Duration(days: 5)),
      updatedAt: now.subtract(const Duration(days: 5)),
    ),

    // 5. Pending join request — "Pending" badge
    Session(
      id: 'mock-5',
      title: 'Contemporary Literature Circle',
      subject: Subject.literature,
      description: 'Reading and discussing contemporary novels.',
      visibility: SessionVisibility.approval,
      joinApproval: JoinApproval.hostApproval,
      hostId: 'mock-host-5',
      hostName: 'Mei Lin',
      hostPhotoUrl: null,
      startTime: DateTime(now.year, now.month, now.day + 5, 16, 0),
      endTime: DateTime(now.year, now.month, now.day + 5, 18, 0),
      location: 'Humanities Lounge',
      capacity: 8,
      participantCount: 4,
      hashtags: const ['literature', 'reading', 'discussion'],
      myStatus: JoinStatus.pending,
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(days: 2)),
    ),

    // 6. Hosted by me — "Host" badge (uses real current user UID)
    Session(
      id: 'mock-6',
      title: 'Microeconomics Problem Set',
      subject: Subject.economics,
      description:
          'Working on supply-demand models and market equilibrium problem sets.',
      visibility: SessionVisibility.public,
      hostId: currentUserId,
      hostName: 'You',
      hostPhotoUrl: null,
      startTime: DateTime(now.year, now.month, now.day + 6, 9, 0),
      endTime: DateTime(now.year, now.month, now.day + 6, 11, 0),
      location: 'Social Sciences, Room 305',
      capacity: 6,
      participantCount: 2,
      hashtags: const ['economics', 'microecon'],
      myStatus: JoinStatus.host,
      createdAt: now.subtract(const Duration(hours: 6)),
      updatedAt: now.subtract(const Duration(hours: 6)),
    ),
  ];
}

/// Provides the dashboard's "discover" sessions list.
///
/// Currently mock data. Watches authStateProvider so the mock host session
/// uses the logged-in user's real UID (and thus shows the "Host" badge for them).
///
/// TODO: replace with real Firestore stream from session_service.
final dashboardSessionsProvider = Provider<List<Session>>((ref) {
  final auth = ref.watch(authStateProvider);
  final currentUserId = auth.maybeWhen(
    data: (user) => user?.id ?? 'unknown',
    orElse: () => 'unknown',
  );
  return _generateMockSessions(currentUserId);
});

/// Mock unread notification count.
/// TODO: wire to notification_service when implemented.
final unreadNotificationCountProvider = Provider<int>((ref) => 3);