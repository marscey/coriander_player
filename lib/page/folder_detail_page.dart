import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/component/audio_tile.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/library/audio_library.dart';
import 'package:coriander_player/page/uni_page.dart';
import 'package:coriander_player/page/uni_page_components.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class FolderDetailPage extends StatelessWidget {
  final AudioFolder folder;
  const FolderDetailPage({super.key, required this.folder});

  List<AudioFolder> _getChildFolders() {
    final childFolders = <AudioFolder>{};
    final folderPath = folder.path.endsWith('/') ? folder.path : '${folder.path}/';
    
    for (final audio in folder.audios) {
      if (audio.path.startsWith(folderPath)) {
        final relativePath = audio.path.substring(folderPath.length);
        final firstSlashIndex = relativePath.indexOf('/');
        
        if (firstSlashIndex != -1) {
          final childFolderName = relativePath.substring(0, firstSlashIndex);
          final childFolderPath = folderPath + childFolderName;
          
          // 从音频库中查找匹配的子文件夹
          final matchingFolder = AudioLibrary.instance.folders.firstWhere(
            (f) => f.path == childFolderPath,
            orElse: () => AudioFolder(
              [], // audios
              childFolderPath, // path
              DateTime.now().millisecondsSinceEpoch ~/ 1000, // modified
              DateTime.now().millisecondsSinceEpoch ~/ 1000, // latest
            ),
          );
          
          if (matchingFolder.audios.isNotEmpty) {
            childFolders.add(matchingFolder);
          }
        }
      }
    }
    
    return childFolders.toList()..sort((a, b) => a.path.compareTo(b.path));
  }

  String _getFolderName(String path) {
    return path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    // 只显示当前文件夹的直接音频文件（不包含子文件夹中的文件）
    final contentList = folder.audios.where((a) {
      final folderPath = folder.path.endsWith('/') ? folder.path : '${folder.path}/';
      final relativePath = a.path.substring(folderPath.length);
      return !relativePath.contains('/');
    }).toList();
    
    final childFolders = _getChildFolders();
    final multiSelectController = MultiSelectController<Audio>();
    
    // 合并音频文件和子文件夹
    final allItems = [...contentList, ...childFolders];
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_getFolderName(folder.path)),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "${contentList.length} 首乐曲, ${childFolders.length} 个子文件夹",
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (childFolders.isNotEmpty)
            Container(
              height: 120,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: childFolders.length,
                itemBuilder: (context, index) {
                  final childFolder = childFolders[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FolderDetailPage(folder: childFolder),
                        ),
                      );
                    },
                    child: Container(
                      width: 100,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.folder, size: 48, color: Colors.blue),
                          const SizedBox(height: 4),
                          Text(
                            _getFolderName(childFolder.path),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${childFolder.audios.length} 首',
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: UniPage<Audio>(
              pref: AppPreference.instance.folderDetailPagePref,
              title: "",
              subtitle: "${contentList.length} 首乐曲",
              contentList: contentList,
              contentBuilder: (context, item, i, multiSelectController) => AudioTile(
                audioIndex: i,
                playlist: contentList,
                multiSelectController: multiSelectController,
              ),
              enableShufflePlay: true,
              enableSortMethod: true,
              enableSortOrder: true,
              enableContentViewSwitch: true,
              multiSelectController: multiSelectController,
              multiSelectViewActions: [
                AddAllToPlaylist(multiSelectController: multiSelectController),
                MultiSelectSelectOrClearAll(
                  multiSelectController: multiSelectController,
                  contentList: contentList,
                ),
                MultiSelectExit(multiSelectController: multiSelectController),
              ],
              sortMethods: [
                SortMethodDesc(
                  icon: Symbols.title,
                  name: "标题",
                  method: (list, order) {
                    switch (order) {
                      case SortOrder.ascending:
                        list.sort((a, b) => a.title.localeCompareTo(b.title));
                        break;
                      case SortOrder.decending:
                        list.sort((a, b) => b.title.localeCompareTo(a.title));
                        break;
                    }
                  },
                ),
                SortMethodDesc(
                  icon: Symbols.artist,
                  name: "艺术家",
                  method: (list, order) {
                    switch (order) {
                      case SortOrder.ascending:
                        list.sort((a, b) => a.artist.localeCompareTo(b.artist));
                        break;
                      case SortOrder.decending:
                        list.sort((a, b) => b.artist.localeCompareTo(a.artist));
                        break;
                    }
                  },
                ),
                SortMethodDesc(
                  icon: Symbols.album,
                  name: "专辑",
                  method: (list, order) {
                    switch (order) {
                      case SortOrder.ascending:
                        list.sort((a, b) => a.album.localeCompareTo(b.album));
                        break;
                      case SortOrder.decending:
                        list.sort((a, b) => b.album.localeCompareTo(a.album));
                        break;
                    }
                  },
                ),
                SortMethodDesc(
                  icon: Symbols.add,
                  name: "创建时间",
                  method: (list, order) {
                    switch (order) {
                      case SortOrder.ascending:
                        list.sort((a, b) => a.created.compareTo(b.created));
                        break;
                      case SortOrder.decending:
                        list.sort((a, b) => b.created.compareTo(a.created));
                        break;
                    }
                  },
                ),
                SortMethodDesc(
                  icon: Symbols.edit,
                  name: "修改时间",
                  method: (list, order) {
                    switch (order) {
                      case SortOrder.ascending:
                        list.sort((a, b) => a.modified.compareTo(b.modified));
                        break;
                      case SortOrder.decending:
                        list.sort((a, b) => b.modified.compareTo(a.modified));
                        break;
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );

  }
}
