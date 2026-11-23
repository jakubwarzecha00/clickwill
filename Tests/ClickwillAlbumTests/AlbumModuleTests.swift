import Testing
import ClickwillModel
@testable import ClickwillAlbum

@Suite struct AlbumModuleTests {
    @Test func defaultOptionsOpenWithoutTheEditor() {
        let options = AlbumOptions()
        #expect(options.editorShown == false)
        #expect(options.coverFile == nil)
    }
}
