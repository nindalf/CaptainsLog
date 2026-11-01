import Testing
import CaptainsLogKit

struct GitHubRepoTests {
    @Test(arguments: [
        ("nindalf/CaptainsLog", "nindalf/CaptainsLog"),
        ("  nindalf/CaptainsLog \n", "nindalf/CaptainsLog"),
        ("https://github.com/nindalf/CaptainsLog", "nindalf/CaptainsLog"),
        ("https://github.com/nindalf/CaptainsLog/pull/12", "nindalf/CaptainsLog"),
        ("https://github.com/nindalf/CaptainsLog.git", "nindalf/CaptainsLog"),
        ("github.com/nindalf/CaptainsLog/", "nindalf/CaptainsLog"),
        ("git@github.com:nindalf/CaptainsLog.git", "nindalf/CaptainsLog"),
        ("my-org/my_repo.js", "my-org/my_repo.js"),
    ])
    func parses(input: String, expected: String) {
        #expect(GitHubRepo.parse(input) == expected)
    }

    @Test(arguments: ["", "CaptainsLog", "nindalf/", "/CaptainsLog", "nindalf/Captains Log", "a/b/c", "https://github.com/nindalf", "../x"])
    func rejects(input: String) {
        #expect(GitHubRepo.parse(input) == nil)
    }
}
