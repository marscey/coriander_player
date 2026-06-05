use lofty::prelude::{Accessor, AudioFile, ItemKey, TaggedFileExt};
use lofty::file::FileType;
use std::io::Cursor;
use std::path::Path;

fn construct_flac_virtual_file(mut head_bytes: Vec<u8>) -> Vec<u8> {
    if head_bytes.len() < 4 || &head_bytes[0..4] != b"fLaC" {
        return head_bytes;
    }
    let mut offset = 4usize;
    let mut last_complete_block_end = 4usize;
    while offset + 4 <= head_bytes.len() {
        let is_last = (head_bytes[offset] & 0x80) != 0;
        let block_size = ((head_bytes[offset + 1] as usize) << 16)
            | ((head_bytes[offset + 2] as usize) << 8)
            | (head_bytes[offset + 3] as usize);
        let block_end = offset + 4 + block_size;
        if block_end <= head_bytes.len() {
            last_complete_block_end = block_end;
            if is_last {
                head_bytes.truncate(block_end);
                return head_bytes;
            }
            offset = block_end;
        } else {
            break;
        }
    }
    head_bytes.truncate(last_complete_block_end);
    offset = 4;
    while offset + 4 <= last_complete_block_end {
        let block_size = ((head_bytes[offset + 1] as usize) << 16)
            | ((head_bytes[offset + 2] as usize) << 8)
            | (head_bytes[offset + 3] as usize);
        let block_end = offset + 4 + block_size;
        if block_end == last_complete_block_end {
            head_bytes[offset] |= 0x80;
            break;
        }
        offset = block_end;
    }
    head_bytes
}

fn main() {
    let path = std::env::args().nth(1).expect("need file path");
    let data = std::fs::read(&path).expect("failed to read file");
    let file_size = data.len() as u64;
    println!("File: {}", path);
    println!("File size: {} bytes", file_size);

    // 1. read_from_path 基准
    match lofty::read_from_path(&path) {
        Ok(tagged_file) => {
            let props = tagged_file.properties();
            println!("[read_from_path] duration={}s, bitrate={:?}, sample_rate={:?}", 
                props.duration().as_secs(), props.audio_bitrate(), props.sample_rate());
        }
        Err(e) => println!("[read_from_path] error: {}", e),
    }

    // 2. 旧方式：head + zeros + tail
    let head_size = (64 * 1024).min(data.len());
    let tail_size = (128 * 1024).min(data.len());
    let tail_start = file_size.saturating_sub(tail_size as u64) as usize;
    let head_bytes = &data[..head_size];
    let tail_bytes = &data[tail_start..];

    let mut buffer_old = Vec::with_capacity(file_size as usize);
    buffer_old.extend_from_slice(head_bytes);
    if tail_start > head_size { buffer_old.resize(tail_start, 0); }
    if tail_start < head_size { buffer_old.truncate(tail_start); }
    buffer_old.extend_from_slice(tail_bytes);

    let mut cursor_old = Cursor::new(buffer_old);
    match lofty::probe::Probe::with_file_type(&mut cursor_old, FileType::Flac).read() {
        Ok(tagged_file) => {
            let props = tagged_file.properties();
            println!("[OLD head+zeros+tail] duration={}s, bitrate={:?}, sample_rate={:?}", 
                props.duration().as_secs(), props.audio_bitrate(), props.sample_rate());
        }
        Err(e) => println!("[OLD head+zeros+tail] error: {}", e),
    }

    // 3. 新方式：construct_flac_virtual_file
    let flac_buffer = construct_flac_virtual_file(head_bytes.to_vec());
    println!("FLAC virtual file size: {} (original head: {})", flac_buffer.len(), head_bytes.len());

    let mut cursor_new = Cursor::new(flac_buffer);
    match lofty::probe::Probe::with_file_type(&mut cursor_new, FileType::Flac).read() {
        Ok(tagged_file) => {
            let props = tagged_file.properties();
            println!("[NEW construct_flac_virtual_file] duration={}s, bitrate={:?}, sample_rate={:?}", 
                props.duration().as_secs(), props.audio_bitrate(), props.sample_rate());
            
            if let Some(tag) = tagged_file.primary_tag().or_else(|| tagged_file.first_tag()) {
                let artist_strs: Vec<_> = tag.get_strings(&ItemKey::TrackArtist).collect();
                println!("[NEW] title={:?}, artist={:?}, album={:?}, track={:?}", 
                    tag.title(), artist_strs, tag.album(), tag.track());
            }
        }
        Err(e) => println!("[NEW construct_flac_virtual_file] error: {}", e),
    }
}
