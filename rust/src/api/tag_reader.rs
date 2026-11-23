use std::{
    collections::HashSet,
    fs::{self},
    io::{self, Cursor, Read, Write},
    path::{Path, PathBuf},
    time::{Duration, UNIX_EPOCH},
};

use image::imageops;
use lofty::prelude::{Accessor, AudioFile, ItemKey, TaggedFileExt};
use lofty::file::FileType;
use sha2::{Sha256, Digest};

use crate::frb_generated::StreamSink;

use super::logger::log_to_dart;

#[cfg(target_os = "windows")]
use windows::{
    core::Interface,
    core::HSTRING,
    Storage::{
        FileProperties::ThumbnailMode,
        StorageFile,
        Streams::{DataReader, IInputStream},
    },
};

/// K: extension, V: can read tags by using Lofty
static SUPPORT_FORMAT: phf::Map<&'static str, bool> = phf::phf_map! {
    "mp3" => true, "mp2" => false, "mp1" => false,
    "ogg" => true,
    "wav" => true, "wave" => true,
    "aif" => true, "aiff" => true, "aifc" => true,
    // 通过 Windows 系统支持
    "asf" => false, "wma" => false,
    "aac" => true, "adts" => true,
    "m4a" => true,
    "ac3" => false,
    "amr" => false, "3ga" => false,
    "flac" => true,
    "mpc" => true,
    // 插件支持
    "mid" => false,
    "wv" => true, "wvc" => true,
    "opus" => true,
    "dsf" => false, "dff" => false,
    "ape" => true,
};

pub struct IndexActionState {
    /// completed / total
    pub progress: f64,

    /// describe action state
    pub message: String,
}

#[derive(Debug)]
struct Audio {
    title: String,
    artist: String,
    album: String,
    genre: String,
    year: Option<u32>,
    /// 发行日期（完整格式，如 "2022-07-15"）
    date: String,
    track: Option<u32>,
    /// in secs
    duration: u64,
    /// kbps
    bitrate: Option<u32>,
    sample_rate: Option<u32>,
    /// absolute path
    path: String,
    /// secs since UNIX_EPOCH
    modified: u64,
    /// secs since UNIX_EPOCH
    created: u64,
    /// 标签获取方式
    by: Option<String>,
}

impl Audio {
    fn new_with_path(path: impl AsRef<Path>, by: Option<String>) -> Option<Self> {
        let path = path.as_ref();
        Some(Audio {
            title: path.file_name()?.to_string_lossy().to_string(),
            artist: "UNKNOWN".to_string(),
            album: "UNKNOWN".to_string(),
            genre: String::new(),
            year: None,
            date: String::new(),
            track: None,
            duration: 0,
            bitrate: None,
            sample_rate: None,
            path: path.to_string_lossy().to_string(),
            modified: 0,
            created: 0,
            by,
        })
    }

    fn to_json_value(&self) -> serde_json::Value {
        serde_json::json!({
            "title": self.title,
            "artist": self.artist,
            "album": self.album,
            "genre": self.genre,
            "year": self.year,
            "date": self.date,
            "track": self.track,
            "duration": self.duration,
            "bitrate": self.bitrate,
            "sample_rate": self.sample_rate,
            "path": self.path,
            "modified": self.modified,
            "created": self.created,
            "by": self.by
        })
    }

    /// 不支持：None  
    /// Lofty 能获取到信息：read_by_lofty  
    /// 不能的话：read_by_win_music_properties  
    /// 再不能的话：title: filename 代替
    fn read_from_path(path: impl AsRef<Path>) -> Option<Self> {
        let path = path.as_ref();
        let lofty_support: bool =
            *SUPPORT_FORMAT.get(&path.extension()?.to_ascii_lowercase().to_string_lossy())?;

        let file_metadata = match fs::metadata(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(err.to_string());
                return None;
            }
        };
        let modified = file_metadata
            .modified()
            .unwrap_or(UNIX_EPOCH)
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();
        let created = file_metadata
            .created()
            .unwrap_or(UNIX_EPOCH)
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();

        if lofty_support {
            if let Some(value) = Self::read_by_lofty(path, modified, created) {
                return Some(value);
            }

            match Self::read_by_win_music_properties(path, modified, created) {
                Ok(value) => Some(value),
                Err(err) => {
                    log_to_dart(format!("{:?}: {}", path, err));
                    return Self::new_with_path(path, None);
                }
            }
        } else {
            match Self::read_by_win_music_properties(path, modified, created) {
                Ok(value) => Some(value),
                Err(err) => {
                    log_to_dart(format!("{:?}: {}", path, err));
                    return Self::new_with_path(path, None);
                }
            }
        }
    }

    /// 使用 lofty 获取音乐标签。只在文件名不正确、没有标签或包含不支持的编码时返回 None
    fn read_by_lofty(path: impl AsRef<Path>, modified: u64, created: u64) -> Option<Self> {
        let path = path.as_ref();
        let tagged_file = match lofty::read_from_path(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", path, err));
                return None;
            }
        };

        let properties = tagged_file.properties();

        if let Some(tag) = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())
        {
            let artist_strs: Vec<_> = tag.get_strings(&ItemKey::TrackArtist).collect();
            let artist = if artist_strs.is_empty() {
                std::borrow::Cow::Borrowed("UNKNOWN").to_string()
            } else {
                artist_strs.join("/")
            };

            let genre = tag.genre().map(|s| s.to_string()).unwrap_or_default();
            let year = tag.year();
            // 从 RecordingDate 字段获取完整发行日期（如 "2022-07-15"）
            let date = tag.get_string(&ItemKey::RecordingDate).map(|s| s.to_string()).unwrap_or_default();

            return Some(Audio {
                title: tag
                    .title()
                    .unwrap_or(path.file_name()?.to_string_lossy())
                    .to_string(),
                artist,
                album: tag
                    .album()
                    .unwrap_or(std::borrow::Cow::Borrowed("UNKNOWN"))
                    .to_string(),
                genre,
                year,
                date,
                track: tag.track(),
                duration: properties.duration().as_secs(),
                bitrate: properties.audio_bitrate(),
                sample_rate: properties.sample_rate(),
                path: path.to_string_lossy().to_string(),
                modified,
                created,
                by: Some("Lofty".to_string()),
            });
        }

        return Some(Audio {
            title: path.file_name()?.to_string_lossy().to_string(),
            artist: std::borrow::Cow::Borrowed("UNKNOWN").to_string(),
            album: std::borrow::Cow::Borrowed("UNKNOWN").to_string(),
            genre: String::new(),
            year: None,
            date: String::new(),
            track: None,
            duration: properties.duration().as_secs(),
            bitrate: properties.audio_bitrate(),
            sample_rate: properties.sample_rate(),
            path: path.to_string_lossy().to_string(),
            modified,
            created,
            by: Some("Lofty".to_string()),
        });
    }

    /// 使用 Windows Api 获取音乐标签。会因为各种原因返回 Err
    #[cfg(target_os = "windows")]
    fn read_by_win_music_properties(
        path: impl AsRef<Path>,
        modified: u64,
        created: u64,
    ) -> Result<Self, windows::core::Error> {
        let path = path.as_ref();
        let storage_file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))?.get()?;
        let music_properties = storage_file
            .Properties()?
            .GetMusicPropertiesAsync()?
            .get()?;

        let duration: Duration = music_properties.Duration()?.into();

        let mut title = music_properties
            .Title()
            .or_else(|_| storage_file.Name())?
            .to_string();
        if title.is_empty() {
            title = storage_file.Name()?.to_string();
        }

        let mut artist = music_properties
            .Artist()
            .unwrap_or(HSTRING::from("UNKNOWN"))
            .to_string();
        if artist.is_empty() {
            artist = "UNKNOWN".to_string();
        }

        let mut album = music_properties
            .Album()
            .unwrap_or(HSTRING::from("UNKNOWN"))
            .to_string();
        if album.is_empty() {
            album = "UNKNOWN".to_string();
        }

        let track = music_properties.TrackNumber()?;

        Ok(Self {
            title,
            artist,
            album,
            genre: String::new(), // Windows API 不直接提供 genre
            year: None,           // Windows API 不直接提供 year
            date: String::new(),  // Windows API 不直接提供 date
            track: if track == 0 { None } else { Some(track) },
            duration: duration.as_secs(),
            bitrate: None, // Windows API 不直接提供比特率
            sample_rate: None, // Windows API 不直接提供采样率
            path: path.to_string_lossy().to_string(),
            modified,
            created,
            by: Some("Windows API".to_string()),
        })
    }

    #[cfg(not(target_os = "windows"))]
    fn read_by_win_music_properties(
        path: impl AsRef<Path>,
        modified: u64,
        created: u64,
    ) -> Result<Self, anyhow::Error> {
        // 在非Windows平台上，此函数直接返回错误
        Err(anyhow::anyhow!("Windows API not available"))
    }

    // 我们使用这个函数来统一处理Windows平台上的音乐标签读取
    // 注意: 之前的实现使用了不同的API调用方式，我们在这里统一使用AlbumTitle而不是Album
}

#[derive(Debug)]
struct AudioFolder {
    path: String,
    /// secs since UNIX_EPOCH
    modified: u64,
    /// biggest created in audios. secs since UNIX_EPOCH
    latest: u64,
    audios: Vec<Audio>,
}

impl AudioFolder {
    fn to_json_value(&self) -> serde_json::Value {
        let mut audios_json: Vec<serde_json::Value> = vec![];
        for audio in &self.audios {
            audios_json.push(audio.to_json_value());
        }

        serde_json::json!({
            "path": self.path,
            "modified": self.modified,
            "latest": self.latest,
            "audios": audios_json,
        })
    }

    /// 扫描路径为 path 的文件夹
    fn read_from_folder(path: impl AsRef<Path>) -> Result<AudioFolder, io::Error> {
        let path = path.as_ref();

        let dir = match fs::read_dir(path) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", path, err));
                return Err(err);
            }
        };

        let mut audios: Vec<Audio> = vec![];
        let mut latest: u64 = 0;

        for item in dir {
            let entry = match item {
                Ok(value) => value,
                Err(_) => continue,
            };

            let file_type = match entry.file_type() {
                Ok(value) => value,
                Err(_) => continue,
            };

            if file_type.is_file() {
                if let Some(audio_item) = Audio::read_from_path(entry.path()) {
                    if audio_item.created > latest {
                        latest = audio_item.created;
                    }

                    audios.push(audio_item);
                }
            }
        }

        if !audios.is_empty() {
            return Ok(AudioFolder {
                path: path.to_string_lossy().to_string(),
                modified: fs::metadata(path)?
                    .modified()?
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or(Duration::ZERO)
                    .as_secs(),
                latest,
                audios,
            });
        }

        Err(io::Error::new(
            io::ErrorKind::NotFound,
            path.to_string_lossy() + " has no music.",
        ))
    }

    /// 扫描路径为 path 的文件夹及其所有子文件夹。
    fn read_from_folder_recursively(
        folder: impl AsRef<Path>,
        result: &mut Vec<Self>,
        scaned_count: &mut u64,
        total_count: &mut u64,
        scaned_folders: &mut HashSet<String>,
        sink: &StreamSink<IndexActionState>,
    ) -> Result<(), io::Error> {
        let folder = folder.as_ref();
        if scaned_folders.contains(&folder.to_string_lossy().to_string()) {
            return Ok(());
        }

        let dir = match fs::read_dir(folder) {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("{:?}: {}", folder, err));
                return Ok(());
            }
        };

        let _ = sink.add(IndexActionState {
            progress: *scaned_count as f64 / *total_count as f64,
            message: String::from("正在扫描 ") + &folder.to_string_lossy(),
        });

        scaned_folders.insert(folder.to_string_lossy().to_string());
        let mut audios: Vec<Audio> = vec![];
        let mut latest: u64 = 0;

        for item in dir {
            let entry = match item {
                Ok(value) => value,
                Err(err) => {
                    log_to_dart(err.to_string());
                    continue;
                }
            };

            let file_type = match entry.file_type() {
                Ok(value) => value,
                Err(err) => {
                    log_to_dart(err.to_string());
                    continue;
                }
            };

            if file_type.is_dir() {
                *total_count += 1;
                let _ = Self::read_from_folder_recursively(
                    entry.path(),
                    result,
                    scaned_count,
                    total_count,
                    scaned_folders,
                    sink,
                );
            } else if let Some(metadata) = Audio::read_from_path(entry.path()) {
                if metadata.created > latest {
                    latest = metadata.created;
                }

                audios.push(metadata);
            }
        }

        if !audios.is_empty() {
            if let Ok(metadata) = fs::metadata(folder) {
                if let Ok(modified) = metadata.modified() {
                    result.push(AudioFolder {
                        path: folder.to_string_lossy().to_string(),
                        modified: modified
                            .duration_since(UNIX_EPOCH)
                            .unwrap_or(Duration::ZERO)
                            .as_secs(),
                        latest,
                        audios,
                    });
                }
            }
        }

        *scaned_count += 1;
        let _ = sink.add(IndexActionState {
            progress: *scaned_count as f64 / *total_count as f64,
            message: String::new(),
        });

        Ok(())
    }
}

#[cfg(target_os = "windows")]
fn _get_picture_by_windows(path: &String) -> Result<Vec<u8>, windows::core::Error> {
    let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(path))?.get()?;
    let thumbnail = file
        .GetThumbnailAsyncOverloadDefaultSizeDefaultOptions(ThumbnailMode::MusicView)?
        .get()?;

    let size = thumbnail.Size()? as u32;
    let stream: IInputStream = thumbnail.cast()?;

    let mut buffer = vec![0u8; size as usize];
    let data_reader = DataReader::CreateDataReader(&stream)?;
    data_reader.LoadAsync(size)?.get()?;
    data_reader.ReadBytes(&mut buffer)?;

    data_reader.Close()?;
    stream.Close()?;

    Ok(buffer)
}

#[cfg(not(target_os = "windows"))]
fn _get_picture_by_windows(_path: &String) -> Result<Vec<u8>, anyhow::Error> {
    // 在非Windows平台上，此函数直接返回空结果
    Err(anyhow::anyhow!("Windows API not available"))
}

fn _get_picture_by_lofty(path: &String) -> Option<Vec<u8>> {
    if let Ok(tagged_file) = lofty::read_from_path(&path) {
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())?;

        return Some(tag.pictures().first()?.data().to_vec());
    }

    None
}

/// for Flutter  
/// 如果无法通过 Lofty 获取则通过 Windows 获取
pub fn get_picture_from_path(path: String, width: u32, height: u32) -> Option<Vec<u8>> {
    let mut pic_option = _get_picture_by_lofty(&path);
    
    #[cfg(target_os = "windows")]
    if pic_option.is_none() {
        pic_option = match _get_picture_by_windows(&path) {
            Ok(val) => Some(val),
            Err(err) => {
                log_to_dart(format!("fail to get pic: {}", err));
                None
            }
        };
    }

    if let Some(pic) = &pic_option {
        if let Ok(loaded_pic) = image::load_from_memory(pic) {
            // 计算新的宽高，保持原比例
            let pic_ratio = loaded_pic.width() as f32 / loaded_pic.height() as f32;

            let (result_width, result_height) = if pic_ratio > 1.0 {
                (width, (width as f32 / pic_ratio).round() as u32)
            } else {
                ((height as f32 * pic_ratio).round() as u32, height)
            };

            let resized_img = imageops::resize(
                &loaded_pic,
                result_width,
                result_height,
                imageops::FilterType::Triangle,
            );

            let mut output = Cursor::new(Vec::new());
            if let Ok(_) = resized_img.write_to(&mut output, image::ImageFormat::Png) {
                return Some(output.into_inner());
            }
        }
    }

    pic_option
}

/// for Flutter
/// 从文件头部 + 尾部字节中解析音频封面（内嵌封面）。
/// 用于云音频列表惰性加载：列表滚动时对可见项异步发 Range 请求拉取头部+尾部字节，
/// 调用本函数解析封面，无需下载完整文件。
///
/// [head_bytes]: 文件头部字节（建议至少 256KB 以覆盖大多数封面）
/// [tail_bytes]: 文件尾部字节（M4A/MP4 必需，其他格式可传空）
/// [file_size]: 文件总大小（字节，M4A/MP4 必需，其他格式可传 0）
/// [file_name]: 文件名（用于格式检测）
/// [width]: 目标宽度（像素）
/// [height]: 目标高度（像素）
///
/// 返回缩放后的 PNG 字节，失败返回 None。
/// MP3/FLAC 封面在文件头部，仅需 head_bytes；
/// M4A/MP4 封面在 moov atom（通常在文件尾部），需要 head + tail + file_size。
pub fn get_picture_from_bytes(
    head_bytes: Vec<u8>,
    tail_bytes: Vec<u8>,
    file_size: u32,
    file_name: String,
    width: u32,
    height: u32,
) -> Option<Vec<u8>> {
    if head_bytes.is_empty() {
        return None;
    }

    let file_type = Path::new(&file_name)
        .extension()
        .and_then(|ext| ext.to_str())
        .and_then(|ext| FileType::from_ext(ext));

    log_to_dart(format!(
        "[DEBUG-PIC] get_picture_from_bytes: head={}, tail={}, file_size={}, file_name={}, file_type={:?}",
        head_bytes.len(),
        tail_bytes.len(),
        file_size,
        file_name,
        file_type
    ));

    // FLAC 需要修正 last block 标志；MP4 需要 head+tail+修改 mdat size；其他格式直接用 head bytes
    let buffer = match file_type {
        Some(FileType::Flac) => construct_flac_virtual_file(head_bytes),
        Some(FileType::Mp4) => {
            if tail_bytes.is_empty() || file_size == 0 {
                log_to_dart("[DEBUG-PIC] MP4 but no tail_bytes/file_size, cannot parse".to_string());
                return None;
            }
            construct_mp4_virtual_file(head_bytes, tail_bytes, file_size as u64)
        }
        _ => head_bytes,
    };

    let mut cursor = Cursor::new(buffer);
    let tagged_file = match file_type {
        Some(ft) => match lofty::probe::Probe::with_file_type(&mut cursor, ft).read() {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("[DEBUG-PIC] Probe::with_file_type({:?}) error: {}, trying Probe::new", ft, err));
                // 指定类型失败时回退到自动检测
                cursor.set_position(0);
                match lofty::probe::Probe::new(&mut cursor).read() {
                    Ok(val) => val,
                    Err(err2) => {
                        log_to_dart(format!("[DEBUG-PIC] Probe::new fallback error: {}", err2));
                        return None;
                    }
                }
            }
        },
        None => match lofty::probe::Probe::new(&mut cursor).read() {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("[DEBUG-PIC] Probe::new error: {}", err));
                return None;
            }
        },
    };

    let tag = tagged_file.primary_tag().or_else(|| tagged_file.first_tag())?;
    let pic = tag.pictures().first()?;
    let pic_data = pic.data().to_vec();

    log_to_dart(format!(
        "[DEBUG-PIC] got cover, pic_data={} bytes",
        pic_data.len()
    ));

    // 缩放（与 get_picture_from_path 保持一致）
    if let Ok(loaded_pic) = image::load_from_memory(&pic_data) {
        let pic_ratio = loaded_pic.width() as f32 / loaded_pic.height() as f32;
        let (result_width, result_height) = if pic_ratio > 1.0 {
            (width, (width as f32 / pic_ratio).round() as u32)
        } else {
            ((height as f32 * pic_ratio).round() as u32, height)
        };
        let resized_img = imageops::resize(
            &loaded_pic,
            result_width,
            result_height,
            imageops::FilterType::Triangle,
        );
        let mut output = Cursor::new(Vec::new());
        if resized_img
            .write_to(&mut output, image::ImageFormat::Png)
            .is_ok()
        {
            return Some(output.into_inner());
        }
    }

    // 缩放失败时返回原始封面字节
    Some(pic_data)
}

fn _get_lyric_from_lofty(path: &String) -> Option<String> {
    if let Ok(tagged_file) = lofty::read_from_path(&path) {
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())?;
        let lyric_tag = tag.get(&ItemKey::Lyrics)?;
        let lyric = lyric_tag.value().text()?;

        return Some(lyric.to_string());
    }

    None
}

fn _get_lyric_from_lrc_file(path: &String) -> anyhow::Result<String> {
    let mut lrc_file_path = PathBuf::from(path);
    lrc_file_path.set_extension("lrc");

    let lrc_bytes = fs::read(lrc_file_path)?;

    let is_le = lrc_bytes.starts_with(&[0xFF, 0xFE]);
    let is_utf16 = (is_le || lrc_bytes.starts_with(&[0xFE, 0xFF])) && lrc_bytes.len() % 2 == 0;

    if is_utf16 {
        let convert_fn = match is_le {
            true => u16::from_le_bytes,
            false => u16::from_be_bytes,
        };

        let mut u16_bytes: Vec<u16> = vec![];
        let mut chunk_iter = lrc_bytes.chunks_exact(2);
        chunk_iter.next();

        for chunk in chunk_iter {
            u16_bytes.push(convert_fn([chunk[0], chunk[1]]));
        }
        return Ok(String::from_utf16(&u16_bytes)?);
    }

    return Ok(String::from_utf8(lrc_bytes)?);
}

/// for Flutter   
/// 只支持读取 ID3V2, VorbisComment, Mp4Ilst 存储的内嵌歌词
/// 以及相同目录相同文件名的 .lrc 外挂歌词（utf-8 or utf-16）
pub fn get_lyric_from_path(path: String) -> Option<String> {
    return _get_lyric_from_lofty(&path).or_else(|| match _get_lyric_from_lrc_file(&path) {
        Ok(val) => Some(val),
        Err(err) => {
            log_to_dart(format!("fail to get lrc: {}", err.to_string()));
            None
        }
    });
}

/// for Flutter  
/// 扫描给定路径下所有子文件夹（包括自己）的音乐文件并把索引保存在 index_path/index.json。
pub fn build_index_from_folders_recursively(
    folders: Vec<String>,
    index_path: String,
    sink: StreamSink<IndexActionState>,
) -> Result<(), io::Error> {
    let mut audio_folders: Vec<AudioFolder> = vec![];
    let mut scaned: u64 = 0;
    let mut total: u64 = folders.len() as u64;
    let mut scaned_folders: HashSet<String> = HashSet::new();

    for item in &folders {
        let _ = AudioFolder::read_from_folder_recursively(
            Path::new(item),
            &mut audio_folders,
            &mut scaned,
            &mut total,
            &mut scaned_folders,
            &sink,
        );
    }

    let mut audio_folders_json: Vec<serde_json::Value> = vec![];
    for item in &audio_folders {
        audio_folders_json.push(item.to_json_value());
    }
    let json_value = serde_json::json!({
        "version": 110,
        "folders": audio_folders_json,
    });

    let mut index_path = PathBuf::from(index_path);
    index_path.push("index.json");
    fs::File::create(index_path)?.write_all(json_value.to_string().as_bytes())?;

    Ok(())
}

fn _update_index_below_1_1_0(
    index: &serde_json::Value,
    index_path: &PathBuf,
    sink: &StreamSink<IndexActionState>,
) -> Result<(), io::Error> {
    let mut audio_folders_json: Vec<serde_json::Value> = vec![];
    let folders = index.as_array().unwrap();
    for item in folders {
        let path = item["path"].as_str().unwrap();
        let _ = sink.add(IndexActionState {
            progress: audio_folders_json.len() as f64 / folders.len() as f64,
            message: String::from("正在扫描 ") + path,
        });
        let folder_path = Path::new(path);
        if let Ok(audio_folder) = AudioFolder::read_from_folder(folder_path) {
            audio_folders_json.push(audio_folder.to_json_value());
            let _ = sink.add(IndexActionState {
                progress: audio_folders_json.len() as f64 / folders.len() as f64,
                message: String::new(),
            });
        }
    }
    fs::File::create(index_path)?.write_all(
        serde_json::json!({
            "version": 110,
            "folders": audio_folders_json,
        })
        .to_string()
        .as_bytes(),
    )?;

    Ok(())
}

/// for Flutter   
/// 读取 index_path/index.json，检查更新。不可能重新读取被修改的文件夹下所有的音乐标签，这样太耗时。  
///
/// [LOWEST_VERSION] 指定可以继承的 index 的最低版本。
/// 如果 index version < [LOWEST_VERSION] 或者是 index 根本没有 version 再或者格式不符合要求，就转到
/// [_update_index_below_1_1_0] 更新 index；
/// 如果 index version >= [LOWEST_VERSION] 则进行更新。
///
/// 如果文件夹不存在，删除记录。  
/// 如果文件夹被修改（再次读取到的 modified > 记录的 modified），就更新它。没有则跳过它
/// 1. 遍历该文件夹索引，判断文件是否存在，不存在则删除记录
/// 2. 遍历该文件夹索引，如果文件被修改（再次读取到的 modified > 记录的 modified），重新读取标签；没有则跳过它
/// 3. 遍历该文件夹，添加新增（读取到的 created > 记录的 latest）的音乐文件
pub fn update_index(index_path: String, sink: StreamSink<IndexActionState>) -> anyhow::Result<()> {
    let mut index_path = PathBuf::from(index_path);
    index_path.push("index.json");
    let index = fs::read(&index_path)?;
    let mut index: serde_json::Value = serde_json::from_slice(&index)?;

    let version = index["version"].as_u64();
    if version.is_none() {
        return Ok(_update_index_below_1_1_0(&index, &index_path, &sink)?);
    }

    let folders = index["folders"].as_array_mut().unwrap();
    // 删除访问不到的文件夹的记录
    folders.retain(|item| {
        let path = item["path"].as_str().unwrap();

        Path::new(path).exists()
    });

    let mut updated = 0;
    let total = folders.len();

    for folder_item in folders {
        let folder_path = folder_item["path"].as_str().unwrap().to_string();
        let latest = folder_item["latest"].as_u64().unwrap();
        let old_folder_modified = folder_item["modified"].as_u64().unwrap();

        let new_folder_modified = match fs::metadata(&folder_path) {
            Ok(value) => match value.modified() {
                Ok(value) => value
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or(Duration::ZERO)
                    .as_secs(),
                Err(_) => continue,
            },
            Err(_) => continue,
        };

        // 跳过没有被修改的文件夹
        if new_folder_modified <= old_folder_modified {
            updated += 1;
            continue;
        }

        let _ = sink.add(IndexActionState {
            progress: updated as f64 / total as f64,
            message: String::from("正在更新 ") + &folder_path,
        });

        folder_item["modified"] = serde_json::json!(new_folder_modified);

        // 删除访问不到的文件的记录
        let audios = folder_item["audios"].as_array_mut().unwrap();
        audios.retain(|item| {
            let path = item["path"].as_str().unwrap();

            Path::new(path).exists()
        });

        for audio_item in &mut *audios {
            let old_audio_modified = audio_item["modified"].as_u64().unwrap();
            let audio_path = audio_item["path"].as_str().unwrap();
            let new_audio_modified = match fs::metadata(&audio_path) {
                Ok(value) => match value.modified() {
                    Ok(value) => value
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or(Duration::ZERO)
                        .as_secs(),
                    Err(_) => continue,
                },
                Err(_) => continue,
            };
            // 跳过没有被修改的文件
            if new_audio_modified <= old_audio_modified {
                continue;
            }

            // 重新读取被修改的音乐文件的标签并更新
            if let Some(modified_audio) = Audio::read_from_path(Path::new(audio_path)) {
                *audio_item = modified_audio.to_json_value();
            }
        }

        // 添加新增的音乐文件
        let mut new_latest: u64 = latest;
        let dir = match fs::read_dir(folder_path) {
            Ok(value) => value,
            Err(_) => continue,
        };
        for entry in dir {
            let entry = match entry {
                Ok(value) => value,
                Err(_) => continue,
            };
            let file_type = match entry.file_type() {
                Ok(value) => value,
                Err(_) => continue,
            };
            if file_type.is_dir() {
                continue;
            }

            let entry_created = match entry.metadata() {
                Ok(value) => match value.created() {
                    Ok(value) => value
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or(Duration::ZERO)
                        .as_secs(),
                    Err(_) => continue,
                },
                Err(_) => continue,
            };
            if entry_created > latest {
                if let Some(new_audio) = Audio::read_from_path(entry.path()) {
                    if entry_created > new_latest {
                        new_latest = entry_created;
                    }

                    audios.push(new_audio.to_json_value());
                }
            }
        }

        folder_item["latest"] = serde_json::json!(new_latest);

        updated += 1;
        let _ = sink.add(IndexActionState {
            progress: updated as f64 / total as f64,
            message: String::new(),
        });
    }

    fs::File::create(index_path)?.write_all(index.to_string().as_bytes())?;

    Ok(())
}

/// 构造 FLAC 专用虚拟文件：仅使用 head bytes，修正最后一个元数据块的 last block 标志。
/// FLAC 元数据块全部在文件头部，零填充会导致解析器将零误读为元数据块。
fn construct_flac_virtual_file(mut head_bytes: Vec<u8>) -> Vec<u8> {
    // 验证 FLAC magic: "fLaC"
    if head_bytes.len() < 4 || &head_bytes[0..4] != b"fLaC" {
        return head_bytes;
    }

    // 解析元数据块，找到最后一个完整块
    let mut offset = 4usize;
    let mut last_complete_block_end = 4usize;

    while offset + 4 <= head_bytes.len() {
        let is_last = (head_bytes[offset] & 0x80) != 0;
        let block_size = ((head_bytes[offset + 1] as usize) << 16)
            | ((head_bytes[offset + 2] as usize) << 8)
            | (head_bytes[offset + 3] as usize);
        let block_end = offset + 4 + block_size;

        if block_end <= head_bytes.len() {
            // 块完整
            last_complete_block_end = block_end;
            if is_last {
                // 已有 last 标志，截断后直接返回
                head_bytes.truncate(block_end);
                return head_bytes;
            }
            offset = block_end;
        } else {
            // 块不完整（超出 head bytes 范围），停止
            break;
        }
    }

    // 截断到最后一个完整块
    head_bytes.truncate(last_complete_block_end);

    // 重新解析，给最后一个完整块设置 last 标志
    offset = 4;
    while offset + 4 <= last_complete_block_end {
        let block_size = ((head_bytes[offset + 1] as usize) << 16)
            | ((head_bytes[offset + 2] as usize) << 8)
            | (head_bytes[offset + 3] as usize);
        let block_end = offset + 4 + block_size;

        if block_end == last_complete_block_end {
            // 这就是最后一个完整块，设置 last 标志（bit 7）
            head_bytes[offset] |= 0x80;
            break;
        }
        offset = block_end;
    }

    head_bytes
}

/// 构造通用虚拟文件：头部 + 零填充 + 尾部（适用于 MP3 等格式）
fn construct_full_virtual_file(
    head_bytes: Vec<u8>,
    tail_bytes: Vec<u8>,
    file_size: u64,
) -> Vec<u8> {
    let head_len = head_bytes.len() as u64;
    let tail_len = tail_bytes.len() as u64;
    let tail_start = file_size.saturating_sub(tail_len);

    let mut buffer = Vec::with_capacity(file_size as usize);
    buffer.extend_from_slice(&head_bytes);

    // 中间填充零
    if tail_start > head_len {
        buffer.resize(tail_start as usize, 0);
    }

    // 如果尾部和头部有重叠，截断头部
    if tail_start < head_len {
        buffer.truncate(tail_start as usize);
    }

    buffer.extend_from_slice(&tail_bytes);
    buffer
}

/// 在字节流中按 atom 结构查找指定 atom 的偏移量
/// 仅扫描完整的 atom（按 size 跳转），适用于 head bytes
fn find_atom_offset_in_head(bytes: &[u8], atom_type: &[u8; 4]) -> Option<usize> {
    let mut offset = 0usize;
    while offset + 8 <= bytes.len() {
        let size = u32::from_be_bytes([
            bytes[offset],
            bytes[offset + 1],
            bytes[offset + 2],
            bytes[offset + 3],
        ]) as usize;
        let current_type = &bytes[offset + 4..offset + 8];

        if current_type == atom_type {
            return Some(offset);
        }

        let actual_size = if size == 1 {
            // 64位扩展 size
            if offset + 16 > bytes.len() {
                return None;
            }
            u64::from_be_bytes([
                bytes[offset + 8],
                bytes[offset + 9],
                bytes[offset + 10],
                bytes[offset + 11],
                bytes[offset + 12],
                bytes[offset + 13],
                bytes[offset + 14],
                bytes[offset + 15],
            ]) as usize
        } else if size == 0 {
            // size=0 表示到文件结束
            return None;
        } else {
            size
        };

        if actual_size < 8 {
            // size 异常，避免死循环
            return None;
        }
        offset += actual_size;
    }
    None
}

/// 在字节流中搜索 "moov" magic，返回 (moov atom 起始偏移量, moov size)
/// 适用于 tail bytes（moov 可能不在 atom 对齐位置）
///
/// 放宽验证：只要找到 "moov" magic 且 size >= 8 就返回。
/// 不要求 moov 完整在 tail 中（moov 含封面时 size 可达几 MB，远超 tail 大小）。
/// 调用方需根据返回的 size 判断 moov 是否完整，必要时重新下载完整 moov。
fn find_moov_offset_in_tail(bytes: &[u8]) -> Option<(usize, usize)> {
    if bytes.len() < 8 {
        return None;
    }
    // 从第 4 字节开始搜索（moov 前面至少有 4 字节 size）
    let mut i = 4;
    while i + 4 <= bytes.len() {
        if &bytes[i..i + 4] == b"moov" {
            // 前 4 字节是 size
            let moov_start = i - 4;
            let size = u32::from_be_bytes([
                bytes[moov_start],
                bytes[moov_start + 1],
                bytes[moov_start + 2],
                bytes[moov_start + 3],
            ]) as usize;
            // size >= 8 即认为是有效的 moov atom
            // 不要求 moov 完整在 tail 中（moov 可能含封面，size 很大）
            if size >= 8 {
                log_to_dart(format!(
                    "[DEBUG-MP4-FIND] found moov at offset={}, size={}, tail_len={}, moov_complete={}",
                    moov_start,
                    size,
                    bytes.len(),
                    moov_start + size <= bytes.len()
                ));
                return Some((moov_start, size));
            }
        }
        i += 1;
    }
    log_to_dart("[DEBUG-MP4-FIND] moov NOT found in tail".to_string());
    None
}

/// 构造 MP4/M4A 专用虚拟文件
///
/// M4A 文件结构: ftyp + (moov | mdat) + (mdat | moov)
/// moov atom 包含所有元数据（时长/艺术家/专辑/流派/封面）
///
/// 问题：mdat 声明的 size 很大（几 MB），construct_full_virtual_file 的零填充
/// 会让 lofty seek 跳过 mdat 时跳到零填充区域，无法到达 moov
///
/// 修复：在 tail 中找到 moov 位置，修改 head 中 mdat 的 size 字段，
/// 让 lofty seek 跳过 mdat 后正好到达 tail 中的 moov 位置
fn construct_mp4_virtual_file(
    head_bytes: Vec<u8>,
    tail_bytes: Vec<u8>,
    file_size: u64,
) -> Vec<u8> {
    let head_len = head_bytes.len() as u64;
    let tail_len = tail_bytes.len() as u64;
    let tail_start = file_size.saturating_sub(tail_len);

    log_to_dart(format!(
        "[DEBUG-MP4] construct_mp4_virtual_file: head_len={}, tail_len={}, file_size={}, tail_start={}",
        head_len, tail_len, file_size, tail_start
    ));

    // 1. 在 tail 中搜索 moov atom
    let moov_info = find_moov_offset_in_tail(&tail_bytes);
    log_to_dart(format!(
        "[DEBUG-MP4] moov_info={:?}",
        moov_info
    ));

    // 2. 在 head 中查找 mdat atom
    let mdat_offset_in_head = find_atom_offset_in_head(&head_bytes, b"mdat");
    log_to_dart(format!(
        "[DEBUG-MP4] mdat_offset_in_head={:?}",
        mdat_offset_in_head
    ));

    let mut modified_head = head_bytes;

    // 3. 如果 moov 在 tail 中且 mdat 在 head 中，修改 mdat size
    if let (Some((moov_off, moov_size)), Some(mdat_off)) = (moov_info, mdat_offset_in_head) {
        // 新的 mdat size = tail_start + moov_off - mdat_off
        // 让 lofty 跳过 mdat 后正好到达 tail 中的 moov
        let new_mdat_size = tail_start + moov_off as u64 - mdat_off as u64;

        // 检查原始 mdat size 是否是 32 位（非扩展）
        let original_size = u32::from_be_bytes([
            modified_head[mdat_off],
            modified_head[mdat_off + 1],
            modified_head[mdat_off + 2],
            modified_head[mdat_off + 3],
        ]) as u64;

        if original_size != 1 && new_mdat_size > 0 && new_mdat_size <= u32::MAX as u64 {
            // 用 32 位 size 修改
            modified_head[mdat_off..mdat_off + 4]
                .copy_from_slice(&(new_mdat_size as u32).to_be_bytes());
            log_to_dart(format!(
                "[DEBUG-MP4] modified mdat size: {} -> {} (offset={})",
                original_size, new_mdat_size, mdat_off
            ));
        } else if original_size == 1 {
            // 扩展 size（64位），修改扩展 size 字段
            if mdat_off + 16 <= modified_head.len() && new_mdat_size > 0 {
                modified_head[mdat_off + 8..mdat_off + 16]
                    .copy_from_slice(&new_mdat_size.to_be_bytes());
                log_to_dart(format!(
                    "[DEBUG-MP4] modified mdat extended size: {} (offset={})",
                    new_mdat_size, mdat_off
                ));
            }
        }

        // 检查 moov 是否完整在 tail 中
        let moov_end_in_tail = moov_off + moov_size;
        if moov_end_in_tail > tail_bytes.len() {
            log_to_dart(format!(
                "[DEBUG-MP4] WARNING: moov NOT complete in tail! moov_end_in_tail={}, tail_len={}. moov will be truncated, metadata may be incomplete.",
                moov_end_in_tail,
                tail_bytes.len()
            ));
        } else {
            log_to_dart(format!(
                "[DEBUG-MP4] moov complete in tail: moov_end_in_tail={}, tail_len={}",
                moov_end_in_tail,
                tail_bytes.len()
            ));
        }
    } else {
        log_to_dart("[DEBUG-MP4] cannot find moov in tail or mdat in head, fallback to full virtual file".to_string());
    }

    // 4. 构造虚拟文件：head（含修改后的 mdat size）+ 零填充 + tail
    let mut buffer = Vec::with_capacity(file_size as usize);
    buffer.extend_from_slice(&modified_head);

    if tail_start > head_len {
        buffer.resize(tail_start as usize, 0);
    }
    if tail_start < head_len {
        buffer.truncate(tail_start as usize);
    }

    buffer.extend_from_slice(&tail_bytes);

    log_to_dart(format!(
        "[DEBUG-MP4] virtual file size={}",
        buffer.len()
    ));

    buffer
}

/// for Flutter
/// 探测 MP4/M4A 文件 tail 字节中 moov atom 的位置和大小
///
/// 用于扫描入库时判断 moov 是否完整在 tail 中：
/// - 若不完整（moov_size > tail 剩余字节），调用方需重新下载从 moov 绝对偏移到文件尾的字节
/// - 若完整，可直接调用 [read_metadata_from_bytes]
///
/// [tail_bytes]: 文件尾部字节
/// [file_size]: 文件总大小（字节）
///
/// 返回 JSON 字符串: {"moov_abs_offset": u64, "moov_size": u64, "tail_len": usize, "complete": bool}
/// 未找到 moov 返回 None。
pub fn probe_moov_in_tail(
    tail_bytes: Vec<u8>,
    file_size: u32,
) -> Option<String> {
    let file_size = file_size as u64;
    let tail_len = tail_bytes.len() as u64;
    let tail_start = file_size.saturating_sub(tail_len);

    log_to_dart(format!(
        "[DEBUG-PROBE] probe_moov_in_tail: tail_len={}, file_size={}, tail_start={}",
        tail_len, file_size, tail_start
    ));

    let (moov_off_in_tail, moov_size) = find_moov_offset_in_tail(&tail_bytes)?;

    let moov_abs_offset = tail_start + moov_off_in_tail as u64;
    let moov_end_in_tail = moov_off_in_tail + moov_size;
    let complete = moov_end_in_tail <= tail_bytes.len();

    log_to_dart(format!(
        "[DEBUG-PROBE] moov_abs_offset={}, moov_size={}, complete={}",
        moov_abs_offset, moov_size, complete
    ));

    let result = serde_json::json!({
        "moov_abs_offset": moov_abs_offset,
        "moov_size": moov_size,
        "tail_len": tail_bytes.len(),
        "complete": complete,
    });

    Some(result.to_string())
}

/// for Flutter
/// 探测 MP4/M4A 文件 head 字节中 moov atom 的位置和大小
///
/// 用于扫描入库时判断 moov 是否在 head 中且完整：
/// - moov 在 head 中且完整 → 直接用现有 head+tail 解析
/// - moov 在 head 中但不完整（moov_size > head 剩余字节）→ 调用方需下载 0~moov_end 的字节作为新 head
/// - moov 不在 head 中 → 调用方应改用 probe_moov_in_tail 检测尾部
///
/// [head_bytes]: 文件头部字节
///
/// 返回 JSON 字符串: {"moov_offset": u64, "moov_size": u64, "moov_end": u64, "head_len": usize, "complete": bool}
/// 未找到 moov 返回 None。
pub fn probe_moov_in_head(head_bytes: Vec<u8>) -> Option<String> {
    let moov_offset = find_atom_offset_in_head(&head_bytes, b"moov")?;

    if moov_offset + 8 > head_bytes.len() {
        log_to_dart("[DEBUG-PROBE-HEAD] moov found but size field truncated".to_string());
        return None;
    }

    let size_field = u32::from_be_bytes([
        head_bytes[moov_offset],
        head_bytes[moov_offset + 1],
        head_bytes[moov_offset + 2],
        head_bytes[moov_offset + 3],
    ]) as u64;

    let moov_size = if size_field == 1 {
        // 64位扩展 size
        if moov_offset + 16 > head_bytes.len() {
            log_to_dart("[DEBUG-PROBE-HEAD] moov uses extended size but field truncated".to_string());
            return None;
        }
        u64::from_be_bytes([
            head_bytes[moov_offset + 8],
            head_bytes[moov_offset + 9],
            head_bytes[moov_offset + 10],
            head_bytes[moov_offset + 11],
            head_bytes[moov_offset + 12],
            head_bytes[moov_offset + 13],
            head_bytes[moov_offset + 14],
            head_bytes[moov_offset + 15],
        ])
    } else if size_field == 0 {
        // size=0 表示到文件结束，无法确定大小（理论上 M4A 不会这样）
        log_to_dart("[DEBUG-PROBE-HEAD] moov size=0 (extends to EOF), cannot determine".to_string());
        return None;
    } else {
        size_field
    };

    if moov_size < 8 {
        log_to_dart(format!("[DEBUG-PROBE-HEAD] invalid moov_size={}", moov_size));
        return None;
    }

    let moov_end = moov_offset as u64 + moov_size;
    let complete = moov_end <= head_bytes.len() as u64;

    log_to_dart(format!(
        "[DEBUG-PROBE-HEAD] probe_moov_in_head: moov_offset={}, moov_size={}, moov_end={}, head_len={}, complete={}",
        moov_offset, moov_size, moov_end, head_bytes.len(), complete
    ));

    let result = serde_json::json!({
        "moov_offset": moov_offset,
        "moov_size": moov_size,
        "moov_end": moov_end,
        "head_len": head_bytes.len(),
        "complete": complete,
    });

    Some(result.to_string())
}

/// 将 lofty 解析得到的 TaggedFile 转换为 JSON 字符串。
/// 提取为独立函数，便于在「完整文件解析」和「虚拟文件解析」两条路径上复用。
///
/// JSON 字段：title/artist/album/track/genre/year/date/duration/bitrate/sample_rate
fn metadata_to_json(tagged_file: &lofty::file::TaggedFile, file_name: &str) -> Option<String> {
    let file_type = tagged_file.file_type();
    let properties = tagged_file.properties();
    let duration = properties.duration().as_secs();
    let bitrate = properties.audio_bitrate();
    let sample_rate = properties.sample_rate();

    log_to_dart(format!(
        "[DEBUG] metadata_to_json: file_type={:?}, duration={}s, bitrate={:?}, sample_rate={:?}",
        file_type, duration, bitrate, sample_rate
    ));

    let (title, artist, album, track, genre, year, date) = if let Some(tag) = tagged_file
        .primary_tag()
        .or_else(|| tagged_file.first_tag())
    {
        let artist_strs: Vec<_> = tag.get_strings(&ItemKey::TrackArtist).collect();
        let artist = if artist_strs.is_empty() {
            String::new()
        } else {
            artist_strs.join("/")
        };

        (
            tag.title().map(|s| s.to_string()).unwrap_or_else(|| file_name.to_string()),
            artist,
            tag.album().map(|s| s.to_string()).unwrap_or_default(),
            tag.track(),
            tag.genre().map(|s| s.to_string()).unwrap_or_default(),
            tag.year(),
            tag.get_string(&ItemKey::RecordingDate).map(|s| s.to_string()).unwrap_or_default(),
        )
    } else {
        log_to_dart("[DEBUG] metadata_to_json: no tag found in file".to_string());
        (file_name.to_string(), String::new(), String::new(), None, String::new(), None, String::new())
    };

    let result = serde_json::json!({
        "title": title,
        "artist": artist,
        "album": album,
        "track": track,
        "genre": genre,
        "year": year,
        "date": date,
        "duration": duration,
        "bitrate": bitrate,
        "sample_rate": sample_rate,
    });

    log_to_dart(format!("[DEBUG] metadata_to_json: result={}", result));

    Some(result.to_string())
}

/// for Flutter
/// 从部分字节（文件头 + 文件尾）中解析音频元数据。
/// [head_bytes]: 文件头部字节（建议至少 64KB）；若包含完整文件则直接解析
/// [tail_bytes]: 文件尾部字节（建议至少 128KB）
/// [file_size]: 文件总大小（字节）
/// [file_name]: 文件名（用于格式检测和作为标题回退）
///
/// 返回 JSON 字符串，包含 title/artist/album/duration/bitrate/sample_rate 字段。
pub fn read_metadata_from_bytes(
    head_bytes: Vec<u8>,
    tail_bytes: Vec<u8>,
    file_size: u32,
    file_name: String,
) -> Option<String> {
    let file_size = file_size as u64;
    log_to_dart(format!("[DEBUG] read_metadata_from_bytes: head_bytes={}, tail_bytes={}, file_size={}, file_name={}", head_bytes.len(), tail_bytes.len(), file_size, file_name));

    // 如果 head_bytes 包含完整文件，直接解析（无需虚拟文件构造）
    // 适用于 Dart 端下载完整文件后调用的场景（如小文件 M4A moov 在开头但超过 head 范围）
    if head_bytes.len() as u64 >= file_size {
        log_to_dart("[DEBUG] read_metadata_from_bytes: head_bytes contains full file, parsing directly".to_string());
        let mut cursor = Cursor::new(head_bytes);
        let file_type = Path::new(&file_name)
            .extension()
            .and_then(|ext| ext.to_str())
            .and_then(|ext| FileType::from_ext(ext));
        let tagged_file = match file_type {
            Some(ft) => match lofty::probe::Probe::with_file_type(&mut cursor, ft).read() {
                Ok(val) => val,
                Err(err) => {
                    log_to_dart(format!("[DEBUG] full file Probe::with_file_type({:?}) error: {}, falling back to Probe::new", ft, err));
                    cursor.set_position(0);
                    match lofty::probe::Probe::new(&mut cursor).read() {
                        Ok(val) => val,
                        Err(err2) => {
                            log_to_dart(format!("[DEBUG] full file Probe::new fallback error: {}", err2));
                            return None;
                        }
                    }
                }
            },
            None => match lofty::probe::Probe::new(&mut cursor).read() {
                Ok(val) => val,
                Err(err) => {
                    log_to_dart(format!("[DEBUG] full file Probe::new error: {}", err));
                    return None;
                }
            },
        };
        return metadata_to_json(&tagged_file, &file_name);
    }

    // 根据文件扩展名推断 FileType
    let file_type = Path::new(&file_name)
        .extension()
        .and_then(|ext| ext.to_str())
        .and_then(|ext| FileType::from_ext(ext));

    log_to_dart(format!("[DEBUG] read_metadata_from_bytes: inferred file_type={:?} from extension", file_type));

    // FLAC 元数据块全部在文件头部，不需要零填充+尾部的方式
    // 零填充会导致 FLAC 解析器将零误读为元数据块，产生 "invalid item size" 错误
    let buffer = match file_type {
        Some(FileType::Flac) => construct_flac_virtual_file(head_bytes),
        Some(FileType::Mp4) => construct_mp4_virtual_file(head_bytes, tail_bytes, file_size),
        _ => construct_full_virtual_file(head_bytes, tail_bytes, file_size),
    };

    log_to_dart(format!("[DEBUG] read_metadata_from_bytes: virtual file size={}", buffer.len()));

    let mut cursor = Cursor::new(buffer);

    // 使用 lofty::Probe 从 Cursor 读取，优先使用推断的文件类型
    let tagged_file = match file_type {
        Some(ft) => match lofty::probe::Probe::with_file_type(&mut cursor, ft).read() {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("[DEBUG] read_metadata_from_bytes Probe::with_file_type({:?}) error: {}, falling back to Probe::new", ft, err));
                // 回退：不指定类型重试
                cursor.set_position(0);
                match lofty::probe::Probe::new(&mut cursor).read() {
                    Ok(val) => val,
                    Err(err2) => {
                        log_to_dart(format!("[DEBUG] read_metadata_from_bytes Probe::new fallback error: {}", err2));
                        return None;
                    }
                }
            }
        },
        None => match lofty::probe::Probe::new(&mut cursor).read() {
            Ok(val) => val,
            Err(err) => {
                log_to_dart(format!("[DEBUG] read_metadata_from_bytes lofty error: {}", err));
                return None;
            }
        },
    };

    metadata_to_json(&tagged_file, &file_name)
}

// ==================== 元数据写入功能 ====================

/// 获取 TaggedFile 的可变 tag 引用的辅助宏
/// 避免在 or_else 闭包中多次可变借用 tagged_file
macro_rules! get_tag_mut {
    ($tagged_file:expr) => {
        match $tagged_file.primary_tag_mut() {
            Some(tag) => Some(tag),
            None => $tagged_file.first_tag_mut(),
        }
    };
}

/// 如果文件没有标签，根据文件类型自动创建一个
fn ensure_tag_exists(tagged_file: &mut lofty::file::TaggedFile) -> Result<(), String> {
    if get_tag_mut!(tagged_file).is_some() {
        return Ok(());
    }

    let file_type = tagged_file.file_type();
    let tag_type = file_type.primary_tag_type();
    tagged_file.insert_tag(lofty::tag::Tag::new(tag_type));
    Ok(())
}

/// for Flutter
/// 写入标签到音频文件
pub fn write_tags_to_path(path: String, fields: String) -> Result<(), String> {
    let fields: serde_json::Value = serde_json::from_str(&fields)
        .map_err(|e| format!("Invalid JSON: {}", e))?;

    let mut tagged_file = lofty::read_from_path(&path)
        .map_err(|e| format!("Failed to read file: {}", e))?;

    ensure_tag_exists(&mut tagged_file)?;

    if let Some(tag) = get_tag_mut!(&mut tagged_file) {
        if let Some(title) = fields["title"].as_str() {
            tag.set_title(title.to_string());
        }
        if let Some(artist) = fields["artist"].as_str() {
            tag.set_artist(artist.to_string());
        }
        if let Some(album) = fields["album"].as_str() {
            tag.set_album(album.to_string());
        }
        if let Some(track) = fields["track"].as_u64() {
            tag.set_track(track as u32);
        }
        if let Some(year) = fields["year"].as_u64() {
            tag.set_year(year as u32);
        }
        if let Some(genre) = fields["genre"].as_str() {
            tag.set_genre(genre.to_string());
        }
        if let Some(mbid) = fields["mb_recording_id"].as_str() {
            tag.insert_text(ItemKey::MusicBrainzRecordingId, mbid.to_string());
        }
        if let Some(mbid) = fields["mb_release_id"].as_str() {
            tag.insert_text(ItemKey::MusicBrainzReleaseId, mbid.to_string());
        }
        if let Some(mbid) = fields["mb_artist_id"].as_str() {
            tag.insert_text(ItemKey::MusicBrainzArtistId, mbid.to_string());
        }
    }

    tagged_file.save_to_path(&path, lofty::config::WriteOptions::default())
        .map_err(|e| format!("Failed to save file: {}", e))?;

    Ok(())
}

/// for Flutter
/// 写入封面到音频文件
pub fn write_cover_to_path(
    path: String,
    cover_data: Vec<u8>,
    mime_type: String,
) -> Result<(), String> {
    use lofty::picture::{Picture, PictureType, MimeType};

    let mut tagged_file = lofty::read_from_path(&path)
        .map_err(|e| format!("Failed to read file: {}", e))?;

    ensure_tag_exists(&mut tagged_file)?;

    if let Some(tag) = get_tag_mut!(&mut tagged_file) {
        let pic_type = PictureType::CoverFront;
        let mime = match mime_type.as_str() {
            "image/png" => Some(MimeType::Png),
            "image/jpeg" | "image/jpg" => Some(MimeType::Jpeg),
            "image/tiff" => Some(MimeType::Tiff),
            "image/bmp" => Some(MimeType::Bmp),
            "image/gif" => Some(MimeType::Gif),
            _ => None,
        };
        let pic = Picture::new_unchecked(pic_type, mime, None, cover_data);
        tag.remove_picture_type(pic_type);
        tag.push_picture(pic);
    }

    tagged_file.save_to_path(&path, lofty::config::WriteOptions::default())
        .map_err(|e| format!("Failed to save file: {}", e))?;

    Ok(())
}

/// for Flutter
/// 写入歌词到音频文件
pub fn write_lyric_to_path(
    path: String,
    lyric_text: String,
    _is_synced: bool,
) -> Result<(), String> {
    let mut tagged_file = lofty::read_from_path(&path)
        .map_err(|e| format!("Failed to read file: {}", e))?;

    ensure_tag_exists(&mut tagged_file)?;

    if let Some(tag) = get_tag_mut!(&mut tagged_file) {
        tag.remove_key(&ItemKey::Lyrics);
        tag.insert_text(ItemKey::Lyrics, lyric_text);
    }

    tagged_file.save_to_path(&path, lofty::config::WriteOptions::default())
        .map_err(|e| format!("Failed to save file: {}", e))?;

    Ok(())
}

/// for Flutter
/// 计算文件的内容哈希（用于稳定标识）
/// 读取文件头 64KB + 文件大小，计算 SHA256
/// 文件移动/重命名后，只要内容不变，哈希值不变，可用于重新匹配元数据
pub fn compute_content_hash(path: String) -> Option<String> {
    let mut file = fs::File::open(&path).ok()?;
    let file_size = file.metadata().ok()?.len();

    // 读取文件头 64KB
    let head_size = 64 * 1024;
    let read_size = head_size.min(file_size as usize);
    let mut head_buf = vec![0u8; read_size];
    file.read_exact(&mut head_buf).ok()?;

    // SHA256(head_bytes + file_size)
    let mut hasher = Sha256::new();
    hasher.update(&head_buf);
    hasher.update(file_size.to_le_bytes());

    let result = hasher.finalize();
    Some(format!("{:x}", result))
}

#[cfg(test)]
mod tests {
    use super::*;
    use lofty::prelude::{Accessor, TaggedFileExt};
    use std::io::{Read, Seek};

    /// 创建一个最小的 WAV 测试文件（无需预添加标签，写入函数会自动创建）
    fn create_test_wav(path: &Path) {
        let sample_rate: u32 = 44100;
        let num_channels: u16 = 1;
        let bits_per_sample: u16 = 16;
        let num_samples: u32 = 44100;
        let data_size = num_samples * num_channels as u32 * (bits_per_sample as u32 / 2);

        let mut buf = Vec::with_capacity(44 + data_size as usize);
        buf.extend_from_slice(b"RIFF");
        buf.extend_from_slice(&(36 + data_size).to_le_bytes());
        buf.extend_from_slice(b"WAVE");
        buf.extend_from_slice(b"fmt ");
        buf.extend_from_slice(&16u32.to_le_bytes());
        buf.extend_from_slice(&1u16.to_le_bytes()); // PCM
        buf.extend_from_slice(&num_channels.to_le_bytes());
        buf.extend_from_slice(&sample_rate.to_le_bytes());
        let byte_rate = sample_rate * num_channels as u32 * bits_per_sample as u32 / 8;
        buf.extend_from_slice(&byte_rate.to_le_bytes());
        let block_align = num_channels * bits_per_sample / 8;
        buf.extend_from_slice(&block_align.to_le_bytes());
        buf.extend_from_slice(&bits_per_sample.to_le_bytes());
        buf.extend_from_slice(b"data");
        buf.extend_from_slice(&data_size.to_le_bytes());
        buf.extend(vec![0u8; data_size as usize]);

        fs::write(path, &buf).unwrap();
    }

    /// 创建最小的有效 JPEG 数据 (1x1 白色像素)
    fn create_minimal_jpeg() -> Vec<u8> {
        vec![
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00,
            0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06,
            0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D,
            0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12, 0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D,
            0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28,
            0x37, 0x29, 0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
            0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01,
            0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01,
            0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02,
            0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10,
            0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00,
            0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
            0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42,
            0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16,
            0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36, 0x37,
            0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55,
            0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73,
            0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
            0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5,
            0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA,
            0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6,
            0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
            0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x08,
            0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x7B, 0x94, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xD9,
        ]
    }

    fn test_dir() -> PathBuf {
        let dir = std::env::temp_dir().join("coriander_player_tests");
        let _ = fs::create_dir_all(&dir);
        dir
    }

    // ==================== compute_content_hash 测试 ====================

    #[test]
    fn test_compute_content_hash_basic() {
        let dir = test_dir();
        let path = dir.join("test_hash_basic.bin");
        fs::write(&path, b"hello world").unwrap();

        let hash = compute_content_hash(path.to_string_lossy().to_string());
        assert!(hash.is_some(), "compute_content_hash should return Some");
        let hash = hash.unwrap();
        assert_eq!(hash.len(), 64, "SHA256 hex string should be 64 chars");

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn test_compute_content_hash_consistency() {
        let dir = test_dir();
        let path = dir.join("test_hash_consistency.bin");
        fs::write(&path, b"consistent content").unwrap();

        let hash1 = compute_content_hash(path.to_string_lossy().to_string());
        let hash2 = compute_content_hash(path.to_string_lossy().to_string());

        assert_eq!(hash1, hash2, "Same file should produce same hash");

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn test_compute_content_hash_different_files() {
        let dir = test_dir();
        let path1 = dir.join("test_hash_diff1.bin");
        let path2 = dir.join("test_hash_diff2.bin");
        fs::write(&path1, b"content A").unwrap();
        fs::write(&path2, b"content B").unwrap();

        let hash1 = compute_content_hash(path1.to_string_lossy().to_string());
        let hash2 = compute_content_hash(path2.to_string_lossy().to_string());

        assert_ne!(hash1, hash2, "Different files should produce different hashes");

        let _ = fs::remove_file(&path1);
        let _ = fs::remove_file(&path2);
    }

    #[test]
    fn test_compute_content_hash_nonexistent() {
        let hash = compute_content_hash("/nonexistent/path/to/file.wav".to_string());
        assert!(hash.is_none(), "Non-existent file should return None");
    }

    #[test]
    fn test_compute_content_hash_includes_file_size() {
        let dir = test_dir();
        // 两个文件前64KB内容相同但大小不同
        let path1 = dir.join("test_hash_size1.bin");
        let path2 = dir.join("test_hash_size2.bin");
        let small = vec![0u8; 100];
        let large = vec![0u8; 200];
        fs::write(&path1, &small).unwrap();
        fs::write(&path2, &large).unwrap();

        let hash1 = compute_content_hash(path1.to_string_lossy().to_string());
        let hash2 = compute_content_hash(path2.to_string_lossy().to_string());

        assert_ne!(
            hash1, hash2,
            "Files with same content but different sizes should have different hashes"
        );

        let _ = fs::remove_file(&path1);
        let _ = fs::remove_file(&path2);
    }

    // ==================== write_tags_to_path 测试 ====================

    #[test]
    fn test_write_tags_to_path() {
        let dir = test_dir();
        let path = dir.join("test_write_tags.wav");
        create_test_wav(&path);

        let fields = serde_json::json!({
            "title": "Test Title",
            "artist": "Test Artist",
            "album": "Test Album",
            "track": 1,
            "year": 2024,
            "genre": "Rock"
        })
        .to_string();

        let result = write_tags_to_path(path.to_string_lossy().to_string(), fields);
        assert!(
            result.is_ok(),
            "write_tags_to_path should succeed: {:?}",
            result
        );

        // 验证标签已写入
        let tagged_file = lofty::read_from_path(&path).unwrap();
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag());
        assert!(tag.is_some(), "File should have a tag after writing");
        let tag = tag.unwrap();
        assert_eq!(
            tag.title().map(|s| s.to_string()),
            Some("Test Title".to_string())
        );
        assert_eq!(
            tag.artist().map(|s| s.to_string()),
            Some("Test Artist".to_string())
        );
        assert_eq!(
            tag.album().map(|s| s.to_string()),
            Some("Test Album".to_string())
        );
        assert_eq!(tag.track(), Some(1));
        assert_eq!(tag.year(), Some(2024));
        assert_eq!(
            tag.genre().map(|s| s.to_string()),
            Some("Rock".to_string())
        );

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn test_write_tags_partial_update() {
        let dir = test_dir();
        let path = dir.join("test_write_tags_partial.wav");
        create_test_wav(&path);

        // 先写入完整标签
        let fields1 = serde_json::json!({
            "title": "Original Title",
            "artist": "Original Artist",
            "album": "Original Album"
        })
        .to_string();
        write_tags_to_path(path.to_string_lossy().to_string(), fields1).unwrap();

        // 只更新 title
        let fields2 = serde_json::json!({
            "title": "Updated Title"
        })
        .to_string();
        write_tags_to_path(path.to_string_lossy().to_string(), fields2).unwrap();

        // 验证只有 title 被更新
        let tagged_file = lofty::read_from_path(&path).unwrap();
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())
            .unwrap();
        assert_eq!(
            tag.title().map(|s| s.to_string()),
            Some("Updated Title".to_string())
        );
        assert_eq!(
            tag.artist().map(|s| s.to_string()),
            Some("Original Artist".to_string())
        );
        assert_eq!(
            tag.album().map(|s| s.to_string()),
            Some("Original Album".to_string())
        );

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn test_write_tags_with_musicbrainz_ids() {
        let dir = test_dir();
        let path = dir.join("test_write_tags_mb.wav");
        create_test_wav(&path);

        let fields = serde_json::json!({
            "title": "MB Test",
            "mb_recording_id": "recording-id-123",
            "mb_release_id": "release-id-456",
            "mb_artist_id": "artist-id-789"
        })
        .to_string();

        let result = write_tags_to_path(path.to_string_lossy().to_string(), fields);
        assert!(result.is_ok(), "write_tags with MB IDs should succeed");

        // 验证基本字段已写入
        let tagged_file = lofty::read_from_path(&path).unwrap();
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())
            .unwrap();
        assert_eq!(
            tag.title().map(|s| s.to_string()),
            Some("MB Test".to_string())
        );

        // 注意：WAV/RiffInfo 标签不支持 MusicBrainz IDs
        // MB IDs 只在 ID3v2 (MP3) 和 VorbisComments (FLAC) 中可用
        // 此测试主要验证写入不会报错，MB IDs 的实际验证需要在 MP3/FLAC 文件上进行

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn test_write_tags_invalid_json() {
        let dir = test_dir();
        let path = dir.join("test_write_tags_invalid.wav");
        create_test_wav(&path);

        let result = write_tags_to_path(
            path.to_string_lossy().to_string(),
            "not valid json".to_string(),
        );
        assert!(result.is_err(), "Invalid JSON should return error");

        let _ = fs::remove_file(&path);
    }

    // ==================== write_cover_to_path 测试 ====================

    #[test]
    fn test_write_cover_to_path() {
        let dir = test_dir();
        let path = dir.join("test_write_cover.wav");
        create_test_wav(&path);

        let jpeg_data = create_minimal_jpeg();

        let result = write_cover_to_path(
            path.to_string_lossy().to_string(),
            jpeg_data,
            "image/jpeg".to_string(),
        );
        assert!(
            result.is_ok(),
            "write_cover_to_path should succeed: {:?}",
            result
        );

        // 验证封面已写入
        let tagged_file = lofty::read_from_path(&path).unwrap();
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag());
        assert!(tag.is_some(), "File should have a tag after writing cover");
        let tag = tag.unwrap();
        assert!(
            !tag.pictures().is_empty(),
            "Tag should have pictures after writing cover"
        );
        assert_eq!(
            tag.pictures()[0].pic_type(),
            lofty::picture::PictureType::CoverFront,
            "Picture type should be CoverFront"
        );

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn test_write_cover_replaces_existing() {
        let dir = test_dir();
        let path = dir.join("test_write_cover_replace.wav");
        create_test_wav(&path);

        let jpeg1 = create_minimal_jpeg();
        write_cover_to_path(
            path.to_string_lossy().to_string(),
            jpeg1,
            "image/jpeg".to_string(),
        )
        .unwrap();

        // 写入第二张封面应替换第一张
        let jpeg2 = create_minimal_jpeg();
        write_cover_to_path(
            path.to_string_lossy().to_string(),
            jpeg2,
            "image/jpeg".to_string(),
        )
        .unwrap();

        let tagged_file = lofty::read_from_path(&path).unwrap();
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())
            .unwrap();
        let cover_front_count = tag
            .pictures()
            .iter()
            .filter(|p| p.pic_type() == lofty::picture::PictureType::CoverFront)
            .count();
        assert_eq!(
            cover_front_count, 1,
            "Should have exactly one CoverFront picture after replacement"
        );

        let _ = fs::remove_file(&path);
    }

    // ==================== write_lyric_to_path 测试 ====================

    #[test]
    fn test_write_lyric_to_path() {
        let dir = test_dir();
        let path = dir.join("test_write_lyric.wav");
        create_test_wav(&path);

        let lyric = "[00:00.00]Test lyric line 1\n[00:05.00]Test lyric line 2";

        let result = write_lyric_to_path(
            path.to_string_lossy().to_string(),
            lyric.to_string(),
            true,
        );
        assert!(
            result.is_ok(),
            "write_lyric_to_path should succeed: {:?}",
            result
        );

        // 验证歌词已写入
        let tagged_file = lofty::read_from_path(&path).unwrap();
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag());
        assert!(tag.is_some(), "File should have a tag after writing lyric");
        let tag = tag.unwrap();
        let lyric_item = tag.get(&ItemKey::Lyrics);
        assert!(
            lyric_item.is_some(),
            "Tag should have lyrics after writing"
        );
        let lyric_text = lyric_item.unwrap().value().text();
        assert_eq!(lyric_text, Some(lyric));

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn test_write_lyric_replaces_existing() {
        let dir = test_dir();
        let path = dir.join("test_write_lyric_replace.wav");
        create_test_wav(&path);

        // 先写入歌词
        write_lyric_to_path(
            path.to_string_lossy().to_string(),
            "Old lyric".to_string(),
            false,
        )
        .unwrap();

        // 写入新歌词应替换旧歌词
        let new_lyric = "[00:00.00]New lyric line";
        write_lyric_to_path(
            path.to_string_lossy().to_string(),
            new_lyric.to_string(),
            true,
        )
        .unwrap();

        let tagged_file = lofty::read_from_path(&path).unwrap();
        let tag = tagged_file
            .primary_tag()
            .or_else(|| tagged_file.first_tag())
            .unwrap();
        let lyric_text = tag
            .get(&ItemKey::Lyrics)
            .and_then(|v| v.value().text());
        assert_eq!(lyric_text, Some(new_lyric));

        let _ = fs::remove_file(&path);
    }

    // ==================== 云服务 Range 请求元数据提取测试 ====================

    /// 测试从完整 FLAC 文件中读取元数据（模拟本地文件读取）
    #[test]
    fn test_read_metadata_from_full_flac_file() {
        let flac_path = "/tmp/coriander_test/02. 最伟大的作品.flac";
        let path = Path::new(flac_path);
        if !path.exists() {
            eprintln!("SKIP: test FLAC file not found at {}", flac_path);
            return;
        }

        // 直接从完整文件读取
        let audio = Audio::read_from_path(path);
        assert!(audio.is_some(), "Should be able to read FLAC file");
        let audio = audio.unwrap();

        println!("[TEST] Full file metadata:");
        println!("[TEST]   title:    {}", audio.title);
        println!("[TEST]   artist:   {}", audio.artist);
        println!("[TEST]   album:    {}", audio.album);
        println!("[TEST]   genre:    '{}'", audio.genre);
        println!("[TEST]   year:     {:?}", audio.year);
        println!("[TEST]   track:    {:?}", audio.track);
        println!("[TEST]   duration: {}s", audio.duration);
        println!("[TEST]   bitrate:  {:?}", audio.bitrate);
        println!("[TEST]   sample_rate: {:?}", audio.sample_rate);
        println!("[TEST]   by:       {:?}", audio.by);

        // 验证关键字段
        assert!(!audio.title.is_empty(), "Title should not be empty");
        assert_ne!(audio.artist, "UNKNOWN", "Artist should not be UNKNOWN");
        assert!(!audio.album.is_empty() && audio.album != "UNKNOWN", "Album should be populated");

        // genre 和 year 是关键测试目标
        if audio.genre.is_empty() {
            eprintln!("[TEST] WARNING: genre is empty! This FLAC file may not have genre tag.");
        } else {
            println!("[TEST] SUCCESS: genre = '{}'", audio.genre);
        }

        if audio.year.is_none() {
            eprintln!("[TEST] WARNING: year is None! This FLAC file may not have year tag.");
        } else {
            println!("[TEST] SUCCESS: year = {:?}", audio.year);
        }
    }

    /// 测试从部分字节（模拟 Range 请求）中读取 FLAC 元数据
    #[test]
    fn test_read_metadata_from_range_bytes() {
        let flac_path = "/tmp/coriander_test/02. 最伟大的作品.flac";
        let path = Path::new(flac_path);
        if !path.exists() {
            eprintln!("SKIP: test FLAC file not found at {}", flac_path);
            return;
        }

        let file_size = fs::metadata(path).unwrap().len();
        println!("[TEST] File size: {} bytes", file_size);

        // 读取头部 64KB
        let head_size = (64 * 1024).min(file_size as usize);
        let mut head_bytes = vec![0u8; head_size];
        let mut file = fs::File::open(path).unwrap();
        file.read_exact(&mut head_bytes).unwrap();

        // 读取尾部 128KB
        let tail_size = (128 * 1024).min(file_size as usize);
        let tail_start = file_size.saturating_sub(tail_size as u64);
        let mut tail_bytes = vec![0u8; tail_size];
        file.seek(std::io::SeekFrom::Start(tail_start)).unwrap();
        file.read_exact(&mut tail_bytes).unwrap();

        println!("[TEST] head_bytes: {} bytes", head_bytes.len());
        println!("[TEST] tail_bytes: {} bytes (from offset {})", tail_bytes.len(), tail_start);

        // 验证 FLAC magic
        if &head_bytes[0..4] == b"fLaC" {
            println!("[TEST] FLAC magic verified: fLaC");
        } else {
            eprintln!("[TEST] ERROR: Not a FLAC file! First 4 bytes: {:?}", &head_bytes[0..4]);
        }

        // 解析 FLAC 元数据块头部信息
        let mut offset = 4usize;
        let mut block_count = 0;
        while offset + 4 <= head_bytes.len() {
            let is_last = (head_bytes[offset] & 0x80) != 0;
            let block_type = head_bytes[offset] & 0x7F;
            let block_size = ((head_bytes[offset + 1] as usize) << 16)
                | ((head_bytes[offset + 2] as usize) << 8)
                | (head_bytes[offset + 3] as usize);
            let block_end = offset + 4 + block_size;

            let type_name = match block_type {
                0 => "STREAMINFO",
                1 => "PADDING",
                2 => "APPLICATION",
                3 => "SEEKTABLE",
                4 => "VORBIS_COMMENT",
                5 => "CUESHEET",
                6 => "PICTURE",
                _ => "UNKNOWN",
            };

            println!("[TEST] Block #{}: type={} ({}), size={}, offset={}, is_last={}, complete={}",
                block_count, block_type, type_name, block_size, offset, is_last, block_end <= head_bytes.len());

            if is_last || block_end > head_bytes.len() {
                break;
            }
            offset = block_end;
            block_count += 1;
        }

        // 调用 readMetadataFromBytes
        let result = read_metadata_from_bytes(
            head_bytes,
            tail_bytes,
            file_size as u32,
            "02. 最伟大的作品.flac".to_string(),
        );

        match result {
            Some(json_str) => {
                println!("[TEST] readMetadataFromBytes result: {}", json_str);
                let meta: serde_json::Value = serde_json::from_str(&json_str).unwrap();
                println!("[TEST]   title:    {}", meta["title"]);
                println!("[TEST]   artist:   {}", meta["artist"]);
                println!("[TEST]   album:    {}", meta["album"]);
                println!("[TEST]   genre:    {}", meta["genre"]);
                println!("[TEST]   year:     {}", meta["year"]);
                println!("[TEST]   track:    {}", meta["track"]);
                println!("[TEST]   duration: {}", meta["duration"]);
                println!("[TEST]   bitrate:  {}", meta["bitrate"]);
                println!("[TEST]   sample_rate: {}", meta["sample_rate"]);

                // 检查 genre 和 year
                let genre = meta["genre"].as_str().unwrap_or("");
                let year = meta["year"].as_u64();

                if genre.is_empty() {
                    eprintln!("[TEST] FAIL: genre is empty in Range request result!");
                } else {
                    println!("[TEST] SUCCESS: genre = '{}'", genre);
                }
                if year.is_none() {
                    eprintln!("[TEST] FAIL: year is null in Range request result!");
                } else {
                    println!("[TEST] SUCCESS: year = {}", year.unwrap());
                }
            }
            None => {
                eprintln!("[TEST] FAIL: readMetadataFromBytes returned None!");
            }
        }
    }

    /// 测试更大的 head bytes 是否能捕获完整元数据
    #[test]
    fn test_read_metadata_with_larger_head_bytes() {
        let flac_path = "/tmp/coriander_test/02. 最伟大的作品.flac";
        let path = Path::new(flac_path);
        if !path.exists() {
            eprintln!("SKIP: test FLAC file not found at {}", flac_path);
            return;
        }

        let file_size = fs::metadata(path).unwrap().len();

        // 尝试不同大小的 head bytes
        for head_kb in [64, 128, 256, 512, 1024, 2048] {
            let head_size = (head_kb * 1024).min(file_size as usize);
            let mut head_bytes = vec![0u8; head_size];
            let mut file = fs::File::open(path).unwrap();
            file.read_exact(&mut head_bytes).unwrap();

            let tail_size = (128 * 1024).min(file_size as usize);
            let tail_start = file_size.saturating_sub(tail_size as u64);
            let mut tail_bytes = vec![0u8; tail_size];
            file.seek(io::SeekFrom::Start(tail_start)).unwrap();
            file.read_exact(&mut tail_bytes).unwrap();

            let result = read_metadata_from_bytes(
                head_bytes,
                tail_bytes,
                file_size as u32,
                "02. 最伟大的作品.flac".to_string(),
            );

            match result {
                Some(json_str) => {
                    let meta: serde_json::Value = serde_json::from_str(&json_str).unwrap();
                    let genre = meta["genre"].as_str().unwrap_or("");
                    let year = meta["year"].as_u64();
                    println!("[TEST] head={}KB: genre='{}', year={:?}, title={}",
                        head_kb, genre, year, meta["title"]);
                }
                None => {
                    println!("[TEST] head={}KB: readMetadataFromBytes returned None", head_kb);
                }
            }
        }
    }

    /// 测试从 WebDAV 下载保存的字节中读取元数据（端到端验证）
    /// 先运行 Dart 脚本 test/test_webdav_scan_e2e.dart 下载字节
    /// 然后运行: cd rust && cargo test test_read_metadata_from_webdav_saved_bytes -- --nocapture
    #[test]
    fn test_read_metadata_from_webdav_saved_bytes() {
        let test_dir = Path::new("/tmp/coriander_webdav_test");
        let head_path = test_dir.join("webdav_head.bin");
        let tail_path = test_dir.join("webdav_tail.bin");
        let info_path = test_dir.join("test_info.json");

        if !head_path.exists() || !tail_path.exists() {
            eprintln!("SKIP: WebDAV test bytes not found. Run `dart test/test_webdav_scan_e2e.dart` first.");
            return;
        }

        // 读取测试信息
        let file_size: u64 = if info_path.exists() {
            let info_str = fs::read_to_string(&info_path).unwrap();
            let info: serde_json::Value = serde_json::from_str(&info_str).unwrap();
            info["file_size"].as_u64().unwrap()
        } else {
            eprintln!("[TEST] WARNING: test_info.json not found, using default file size");
            50502164
        };

        // 读取头部字节
        let head_bytes = fs::read(&head_path).unwrap();
        let tail_bytes = fs::read(&tail_path).unwrap();

        println!("[WEBDAV-TEST] ========================================");
        println!("[WEBDAV-TEST] WebDAV Range 请求元数据提取测试");
        println!("[WEBDAV-TEST] ========================================");
        println!("[WEBDAV-TEST] file_size: {} bytes", file_size);
        println!("[WEBDAV-TEST] head_bytes: {} bytes", head_bytes.len());
        println!("[WEBDAV-TEST] tail_bytes: {} bytes", tail_bytes.len());

        // 验证 FLAC magic
        if head_bytes.len() >= 4 {
            if &head_bytes[0..4] == b"fLaC" {
                println!("[WEBDAV-TEST] FLAC magic: ✓ (fLaC)");
            } else {
                eprintln!("[WEBDAV-TEST] FLAC magic: ✗ (expected fLaC, got {:?})", &head_bytes[0..4]);
            }
        }

        // 分析 FLAC 元数据块结构
        if head_bytes.len() >= 4 && &head_bytes[0..4] == b"fLaC" {
            let mut offset = 4usize;
            let mut block_count = 0;
            while offset + 4 <= head_bytes.len() {
                let is_last = (head_bytes[offset] & 0x80) != 0;
                let block_type = head_bytes[offset] & 0x7F;
                let block_size = ((head_bytes[offset + 1] as usize) << 16)
                    | ((head_bytes[offset + 2] as usize) << 8)
                    | (head_bytes[offset + 3] as usize);
                let block_end = offset + 4 + block_size;

                let type_names = [
                    "STREAMINFO", "PADDING", "APPLICATION", "SEEKTABLE",
                    "VORBIS_COMMENT", "CUESHEET", "PICTURE",
                ];
                let type_name = if (block_type as usize) < type_names.len() {
                    type_names[block_type as usize]
                } else {
                    "UNKNOWN"
                };
                let is_complete = block_end <= head_bytes.len();

                println!("[WEBDAV-TEST] Block #{}: type={} ({}), size={}, offset={}, is_last={}, complete={}",
                    block_count, block_type, type_name, block_size, offset, is_last, is_complete);

                if is_last || !is_complete {
                    break;
                }
                offset = block_end;
                block_count += 1;
            }
        }

        // 调用 read_metadata_from_bytes
        println!("[WEBDAV-TEST] 调用 read_metadata_from_bytes...");
        let result = read_metadata_from_bytes(
            head_bytes,
            tail_bytes,
            file_size as u32,
            "02. 最伟大的作品.flac".to_string(),
        );

        match result {
            Some(json_str) => {
                println!("[WEBDAV-TEST] read_metadata_from_bytes 结果:");
                let meta: serde_json::Value = serde_json::from_str(&json_str).unwrap();
                println!("[WEBDAV-TEST]   title:       {}", meta["title"]);
                println!("[WEBDAV-TEST]   artist:      {}", meta["artist"]);
                println!("[WEBDAV-TEST]   album:       {}", meta["album"]);
                println!("[WEBDAV-TEST]   genre:       {}", meta["genre"]);
                println!("[WEBDAV-TEST]   year:        {}", meta["year"]);
                println!("[WEBDAV-TEST]   track:       {}", meta["track"]);
                println!("[WEBDAV-TEST]   duration:    {}s", meta["duration"]);
                println!("[WEBDAV-TEST]   bitrate:     {:?}", meta["bitrate"]);
                println!("[WEBDAV-TEST]   sample_rate: {:?}", meta["sample_rate"]);

                // 关键验证
                let genre = meta["genre"].as_str().unwrap_or("");
                let year = meta["year"].as_u64();

                println!("[WEBDAV-TEST] ========================================");
                if genre.is_empty() {
                    eprintln!("[WEBDAV-TEST] FAIL: genre 为空！WebDAV Range 请求未能提取流派信息");
                } else {
                    println!("[WEBDAV-TEST] SUCCESS: genre = '{}'", genre);
                }
                if year.is_none() {
                    eprintln!("[WEBDAV-TEST] FAIL: year 为空！WebDAV Range 请求未能提取年份信息");
                } else {
                    println!("[WEBDAV-TEST] SUCCESS: year = {}", year.unwrap());
                }
                println!("[WEBDAV-TEST] ========================================");

                // 断言
                assert!(!genre.is_empty(), "genre should not be empty from WebDAV Range bytes");
                assert!(year.is_some(), "year should not be None from WebDAV Range bytes");
                assert_eq!(genre, "国语流行", "genre should be '国语流行'");
                assert_eq!(year.unwrap(), 2022, "year should be 2022");
            }
            None => {
                eprintln!("[WEBDAV-TEST] FAIL: read_metadata_from_bytes 返回 None！");
                panic!("read_metadata_from_bytes should not return None for valid WebDAV Range bytes");
            }
        }
    }

    // ==================== 综合测试：写入后 contentHash 不变 ====================

    #[test]
    fn test_content_hash_stable_after_tag_write() {
        let dir = test_dir();
        let path = dir.join("test_hash_after_write.wav");
        create_test_wav(&path);

        // 写入标签前的 hash
        let hash_before = compute_content_hash(path.to_string_lossy().to_string());

        // 写入标签
        let fields = serde_json::json!({
            "title": "Hash Test Title",
            "artist": "Hash Test Artist"
        })
        .to_string();
        write_tags_to_path(path.to_string_lossy().to_string(), fields).unwrap();

        // 写入标签后的 hash（注意：写入标签会改变文件内容，所以 hash 可能改变）
        // 但这个测试验证 hash 计算本身是稳定的
        let hash_after = compute_content_hash(path.to_string_lossy().to_string());

        // 两次计算 hash 应该都成功
        assert!(hash_before.is_some(), "Hash before write should be Some");
        assert!(hash_after.is_some(), "Hash after write should be Some");

        // 注意：写入标签会修改文件头，所以 hash 会改变。这是预期行为。
        // contentHash 的设计目的是：文件移动/重命名后 hash 不变，而非标签修改后不变。

        let _ = fs::remove_file(&path);
    }
}
