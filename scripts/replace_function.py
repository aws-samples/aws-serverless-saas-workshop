def replace_in_file(str_to_find, replacement_str, file_name):
    fh = open(file_name, "r")
    txt = fh.read()
    ts = txt.split(str_to_find)
    fh.close()
    fh = open(file_name, "w")
    fh.write(ts[0] + replacement_str + ts[1])
    fh.close()
