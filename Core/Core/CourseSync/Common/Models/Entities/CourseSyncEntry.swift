//
// This file is part of Canvas.
// Copyright (C) 2023-present  Instructure, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

struct CourseSyncEntry {
    enum State: Codable, Equatable, Hashable {
        case loading(Float?), error, downloaded
    }

    struct Tab {
        let id: String
        let name: String
        let type: TabName
        var isCollapsed: Bool = true
        var state: State = .loading(nil)
        var selectionState: ListCellView.SelectionState = .deselected
    }

    struct File {
        /**
         The unique identifier of the sync entry in a form of "courses/:courseId/files/:fileId". Doesn't correspond to the file ID on API. Use the `fileId` property if you need the API id.
         */
        let id: String
        var fileId: String { String(id.split(separator: "/").last ?? "") }
        let displayName: String
        let fileName: String
        let url: URL
        let mimeClass: String
        var state: State = .loading(nil)
        var selectionState: ListCellView.SelectionState = .deselected

        /// Filesize in bytes, received from the API.
        let bytesToDownload: Int

        /// Downloaded bytes, progress is persisted to Core Data.
        var bytesDownloaded: Int {
            switch state {
            case .downloaded: return bytesToDownload
            case let .loading(progress):
                if let progress {
                    return Int(Float(bytesToDownload) * progress)
                } else {
                    return 0
                }
            case .error: return 0
            }
        }
    }

    let name: String
    /**
     The unique identifier of the sync entry in a form of "courses/:courseId". Doesn't correspond to the course ID on API. Use the `courseId` property if you need the API id.
     */
    let id: String
    var courseId: String { String(id.split(separator: "/").last ?? "") }

    var tabs: [Self.Tab]
    var selectedTabsCount: Int {
        tabs.reduce(0) { partialResult, tab in
            partialResult + (tab.selectionState == .selected || tab.selectionState == .partiallySelected ? 1 : 0)
        }
    }

    var files: [Self.File]
    var selectedFilesCount: Int {
        files.reduce(0) { partialResult, file in
            partialResult + (file.selectionState == .selected ? 1 : 0)
        }
    }

    var selectionCount: Int {
        (selectedFilesCount + selectedTabsCount) - (selectedFilesCount > 0 ? 1 : 0)
    }

    var isCollapsed: Bool = true
    var selectionState: ListCellView.SelectionState = .deselected
    var isEverythingSelected: Bool = false

    var state: State = .loading(nil)

    /// Total size of course file in bytes.
    var totalSize: Int {
        files
            .reduce(0) { partialResult, file in
                partialResult + file.bytesToDownload
            }
    }

    /// Total size of selected course files in bytes.
    var totalSelectedSize: Int {
        files
            .filter { $0.selectionState == .selected }
            .reduce(0) { partialResult, file in
                partialResult + file.bytesToDownload
            }
    }

    /// Total size of selected and downloaded files in bytes.
    var totalDownloadedSize: Int {
        files
            .filter { $0.selectionState == .selected }
            .reduce(0) { partialResult, file in
                partialResult + file.bytesDownloaded
            }
    }

    /// Total progress of selected file downloads, ranging from 0 to 1.
    var progress: Float {
        let totalProgress = files
            .filter { $0.selectionState == .selected }
            .reduce(0 as Float) { partialResult, file in
                switch file.state {
                case .downloaded: return partialResult + 1
                case let .loading(progress): return partialResult + (progress ?? 0)
                case .error: return partialResult + 0
                }
            }
        return totalProgress / Float(selectedFilesCount)
    }

    mutating func selectCourse(selectionState: ListCellView.SelectionState) {
        tabs.indices.forEach { tabs[$0].selectionState = selectionState }
        files.indices.forEach { files[$0].selectionState = selectionState }
        self.selectionState = selectionState
        isEverythingSelected = selectionState == .selected ? true : false
    }

    mutating func selectTab(index: Int, selectionState: ListCellView.SelectionState) {
        tabs[index].selectionState = selectionState

        if tabs[index].type == .files {
            files.indices.forEach { files[$0].selectionState = selectionState }
        }

        isEverythingSelected = (selectedTabsCount == tabs.count) && (selectedFilesCount == files.count)
        self.selectionState = selectedTabsCount > 0 ? .partiallySelected : .deselected
    }

    mutating func selectFile(index: Int, selectionState: ListCellView.SelectionState) {
        files[index].selectionState = selectionState == .selected ? .selected : .deselected

        isEverythingSelected = (selectedTabsCount == tabs.count) && (selectedFilesCount == files.count)

        guard let fileTabIndex = tabs.firstIndex(where: { $0.type == TabName.files }) else {
            return
        }
        tabs[fileTabIndex].selectionState = selectedFilesCount > 0 ? .partiallySelected : .deselected
        self.selectionState = selectedTabsCount > 0 ? .partiallySelected : .deselected
    }

    mutating func updateCourseState(state: State) {
        self.state = state
    }

    mutating func updateTabState(index: Int, state: State) {
        tabs[index].state = state
    }

    mutating func updateFileState(index: Int, state: State) {
        files[index].state = state
    }
}

extension Array where Element == CourseSyncEntry {
    var totalSelectedSize: Int {
        reduce(0) { partialResult, entry in
            partialResult + entry.totalSelectedSize
        }
    }

    var totalDownloadedSize: Int {
        reduce(0) { partialResult, entry in
            partialResult + entry.totalDownloadedSize
        }
    }

    var progress: Float {
        Float(totalDownloadedSize) / Float(totalSelectedSize)
    }
}

#if DEBUG

extension CourseSyncEntry.File {
    static func make(
        id: String,
        displayName: String,
        fileName: String = "File",
        url: URL = URL(string: "1")!,
        mimeClass: String = "jpg",
        bytesToDownload: Int = 0,
        state: CourseSyncEntry.State = .loading(nil),
        selectionState: ListCellView.SelectionState = .deselected
    ) -> CourseSyncEntry.File {
        .init(
            id: id,
            displayName: displayName,
            fileName: fileName,
            url: url,
            mimeClass: mimeClass,
            state: state,
            selectionState: selectionState,
            bytesToDownload: bytesToDownload
        )
    }
}

#endif