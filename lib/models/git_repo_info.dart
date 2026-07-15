/// Auto-detected identity of a local git repo, read straight from its
/// `.git/config` and `.git/HEAD` — no manual typing needed.
class GitRepoInfo {
  final String owner;
  final String repo;
  final String branch;

  const GitRepoInfo({required this.owner, required this.repo, required this.branch});

  String get fullName => '$owner/$repo';
}
