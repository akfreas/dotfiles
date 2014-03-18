#!/usr/bin/env python
import os
import shutil

def rename_all(root_dir, rename_from, rename_to):

    all_files =  [{'root' : t[0], 'dir' : t[1], 'files' : t[2]} for t in os.walk(root_dir)]
    all_folders = [root[0] for root in os.walk(root_dir) if rename_from]

    for folder in all_folders:
        new_folder = 
        shutil.copytree(folder, 


    filtered_files = []

    for filedict in all_files:

        

        files_in_dir = ["%s/%s" % (filedict['root'], filtered_file) for filtered_file in filedict['files'] if rename_from in filtered_file]
        filtered_files.extend(files_in_dir)




