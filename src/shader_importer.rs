use std::collections::HashMap;


pub struct Importer {
    pub compute: bool,
    pub work_group_count: Option<u32>,
    main_path: String,
    all_imports: HashMap<String, u64>, // includes main / hashmap allows to not care about checking if a path is already there
}

impl Importer {
    pub fn new(path: &str) -> Self {
        let mut hm = HashMap::new();
        hm.insert(path.to_string(), 0);
        Self {
            compute: false,
            work_group_count: None,
            main_path: path.to_string(),
            all_imports: hm,
        }
    }

    pub fn check_and_import(&mut self) -> Option<String> {
        let mut modified: String = "".to_string();
        let mut mod_time: u64 = 0;
        for (path, time) in self.all_imports.iter() {
            let new_time = std::fs::metadata(path).unwrap()
                .modified().unwrap()
                .duration_since(std::time::SystemTime::UNIX_EPOCH).unwrap();
            let new_time = new_time.as_secs() as u64 + new_time.subsec_nanos() as u64; // anything kinda dependent on time will do just fine
            if new_time != *time {
                modified = path.to_string();
                mod_time = new_time;
                break;
            }
        }
        if mod_time == 0 {return None}
        dbg!("something edited");
        let rez = self.update_metadata(&modified).is_none(); // bad file name or something
        self.all_imports.insert(modified, mod_time);
        if rez {return None}
        self.import()
    }

    // update/add all the files imported in this file
    // if already there, update the mod time
    // TODO: merge this with import so that files dont have to be read twice
    fn update_metadata(&mut self, path: &str) -> Option<()> {
        let main_mod = match std::fs::read_to_string(path) {
            Ok(s) => s,
            Err(_) => return None,
        };
        for line in main_mod.lines() {
            if !line.starts_with("/// ") {
                continue;
            }
            let words = line.split_whitespace().collect::<Vec<&str>>();
            match *words.get(1).unwrap_or(&"") {
                "import" => {
                    let path = words[2];
                    if !self.all_imports.contains_key(path) {                        
                        if self.update_file_metadata(path).is_none() {return None}
                    }
                },
                _ => (),
            }
        }
        Some(())
    }

    fn update_file_metadata(&mut self, path: &str) -> Option<()> {
        let new_time = {
            match std::fs::metadata(path) {
                Ok(s) => s.modified().unwrap()
                    .duration_since(std::time::SystemTime::UNIX_EPOCH).unwrap(),
                Err(_) => return None,
            }
        };
        let new_time = new_time.as_secs() as u64 + new_time.subsec_nanos() as u64;
        self.all_imports.insert(path.to_string(), new_time);
        Some(())
    }

    pub fn import(&mut self) -> Option<String> {
        self.compute = false;
        Some(self.import_file(&self.main_path.clone()))
    }

    fn import_file(&mut self, path: &str) -> String {
        //update the stored metadata
        self.update_file_metadata(path);

        let mut shader = "".to_string();
        let main_mod = std::fs::read_to_string(path).unwrap();
        for line in main_mod.lines() {
            if !line.starts_with("/// ") {
                shader.push_str(line);
                shader.push_str("\n");
                continue;
            }
            let words = line.split_whitespace().collect::<Vec<&str>>();
            match *words.get(1).unwrap_or(&"") {
                "import" => { // importing code from other shaders as if it was written in the same file
                    let sub_mod = self.import_file(words[2]);
                    shader.push_str(&sub_mod);
                    shader.push_str("\n");
                },
                "compute_enable" => {
                    self.compute = true;
                },
                "work_group_count" => {
                    self.work_group_count = words.get(2).unwrap_or(&"").parse().ok();
                }
                _ => (),
            }
        }
        shader    
    }
}