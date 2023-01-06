use cmd_lib::run_cmd;

fn year_from_path<P: AsRef<std::path::Path>>(path: P) -> Option<usize> {
    lazy_static::lazy_static! {
        static ref RE_YEAR_RANGE_PRE: regex::Regex = regex::Regex::new(r"^(\d{4})\s*-\s*(\d{4})\s+.*$").unwrap();
        static ref RE_YEAR_RANGE_POST: regex::Regex = regex::Regex::new(r"^.*\s+(\d{4})\s*-\s*(\d{4})$").unwrap();
        static ref RE_YEAR_PRE: regex::Regex = regex::Regex::new(r"^(\d{4})[\s/_]+.*$").unwrap();
        static ref RE_YEAR_POST: regex::Regex = regex::Regex::new(r"^.*[\s/_]+(\d{4})$").unwrap();
        static ref RE_YEAR: regex::Regex = regex::Regex::new(r"^\s*(\d{4})\s*$").unwrap();
    }

    let path = path.as_ref();

    for component in path.iter().rev().filter_map(|s| s.to_str()) {
        if let Some(caps) = RE_YEAR_RANGE_PRE.captures(component) {
            return Some(caps.get(1).unwrap().as_str().parse().unwrap());
        } else if let Some(caps) = RE_YEAR_RANGE_POST.captures(component) {
            return Some(caps.get(1).unwrap().as_str().parse().unwrap());
        } else if let Some(caps) = RE_YEAR_PRE.captures(component) {
            return Some(caps.get(1).unwrap().as_str().parse().unwrap());
        } else if let Some(caps) = RE_YEAR_POST.captures(component) {
            return Some(caps.get(1).unwrap().as_str().parse().unwrap());
        } else if let Some(caps) = RE_YEAR.captures(component) {
            return Some(caps.get(1).unwrap().as_str().parse().unwrap());
        }
    }

    None
}

fn fix_date<P: AsRef<std::path::Path>>(path: P, new_date: &str) {
    let path = path.as_ref();

    if let Err(e) = run_cmd!(exiv2 -M "add Exif.Photo.UserComment estimated_datetime" -M "add Exif.Photo.DateTimeOriginal $new_date" "$path")
    {
        log::error!(
            "can't set date to `{}` in `{}`: {:#?}",
            new_date,
            path.display(),
            e
        );
    }
}

fn main() {
    env_logger::init();

    lazy_static::lazy_static! {
        /// IMG-20210723-WA0006.jpg
        /// PXL_20220423_095259044.MP.jpg
        static ref RE_DATE_IMG: regex::Regex = regex::Regex::new(r"^[A-Z]+[-_](\d{4})(\d{2})(\d{2})[-_].*$").unwrap();
        /// 20221129_104726.jpg
        static ref RE_DATE: regex::Regex = regex::Regex::new(r"^(\d{4})(\d{2})(\d{2})[-_].*$").unwrap();
    }

    let rootdir = std::env::args()
        .nth(1)
        .expect("expected directory argument");
    for entry in walkdir::WalkDir::new(rootdir)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|e| !e.file_type().is_dir())
    {
        let path = entry.path();

        let extension = path
            .extension()
            .and_then(|v| v.to_str())
            .map(|s| s.to_lowercase());
        if !matches!(
            extension.as_deref(),
            Some("jpg" | "jpeg" | "png" | "mp4" | "mpg" | "mpeg" | "avi")
        ) {
            continue;
        }

        if run_cmd!(exiv2 -Pv -K Exif.Photo.DateTimeOriginal "$path" > /dev/null 2>&1).is_ok() {
            continue;
        }

        let stem = path.file_stem().unwrap().to_str().unwrap();

        if let Some(caps) = RE_DATE_IMG.captures(stem) {
            let year: usize = caps.get(1).unwrap().as_str().parse().unwrap();
            let month: usize = caps.get(2).unwrap().as_str().parse().unwrap();
            let day: usize = caps.get(3).unwrap().as_str().parse().unwrap();
            log::trace!("{}: {}-{}-{}", path.display(), year, month, day);

            fix_date(path, &format!("{}:{:02}:{:02} 00:00:00", year, month, day));
        } else if let Some(caps) = RE_DATE.captures(stem) {
            let year: usize = caps.get(1).unwrap().as_str().parse().unwrap();
            let month: usize = caps.get(2).unwrap().as_str().parse().unwrap();
            let day: usize = caps.get(3).unwrap().as_str().parse().unwrap();
            log::trace!("{}: {}-{}-{}", path.display(), year, month, day);

            fix_date(path, &format!("{}:{:02}:{:02} 00:00:00", year, month, day));
        } else if let Some(year) = year_from_path(path) {
            log::trace!("{}: {}", path.display(), year);

            fix_date(path, &format!("{}:01:01 00:00:00", year));
        } else {
            log::error!("UNKNOWN: {}", path.display());
        }
    }

    log::info!("DONE");
}
