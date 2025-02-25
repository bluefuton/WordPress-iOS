import XCTest
@testable import WordPress

class BlogTitleTests: XCTestCase {

    private var blog: Blog!
    private var contextManager: ContextManagerMock!
    private var context: NSManagedObjectContext!

    override func setUp() {
        contextManager = ContextManagerMock()
        context = contextManager.newDerivedContext()
        blog = NSEntityDescription.insertNewObject(forEntityName: "Blog", into: context) as? Blog
        blog.url = Constants.blogURL
        blog.xmlrpc = Constants.blogURL
    }

    func testBlogTitleIsName() throws {
        // Given a blog
        // When blogName is a string
        let blogName = "my blog name"
        blog.settings = newSettings()
        blog.settings?.name = blogName

        // Then blogTitle is blogName
        XCTAssertEqual(blog.title, blogName)
    }

    func testBlogSettingsNameIsNil() throws {
        // Given a blog
        // When blogName is nil
        blog.settings = newSettings()
        blog.settings?.name = nil

        // Then blogTitle is blogDisplayURL
        XCTAssertEqual(blog.title, Constants.blogDisplayURL)
    }

    func testBlogTitleIsDisplayURLWhenTitleNil() throws {
        // Given a blog
        // When a blog has no blogSettings
        // Then blogTitle is blogDisplayURL
        XCTAssertEqual(blog.title, Constants.blogDisplayURL)
    }

    // MARK: - Private Helpers
    fileprivate func newSettings() -> BlogSettings {
        let name = BlogSettings.classNameWithoutNamespaces()
        let entity = NSEntityDescription.insertNewObject(forEntityName: name, into: context)

        return entity as! BlogSettings
    }
}

private extension BlogTitleTests {
    enum Constants {
        static let blogDisplayURL: String = "wordpress.com"
        static let blogURL: String = "http://wordpress.com"
    }
}
