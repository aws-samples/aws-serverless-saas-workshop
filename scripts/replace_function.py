# execute python code to make all edits
# run original script and use labs folder instead of solutions/lab foldere
# done!

def replace_in_file(str_to_find, replacement_str, file_name):
    fh = open(file_name)
    txt = fh.read()
    fh = open(file_name, "w")
    ts = txt.split(str_to_find)
    fh.write(ts[0] + replacement_str + ts[1])
