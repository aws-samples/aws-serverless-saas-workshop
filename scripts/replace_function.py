def replace_in_file(str_to_find, replacement_str, file_name):
    # Read and validate fully before opening for write: opening in "w" mode
    # truncates, so a mismatch here used to leave the file empty.
    with open(file_name, "r") as fh:
        txt = fh.read()

    count = txt.count(str_to_find)
    if count == 0:
        raise SystemExit(
            f"ERROR: search string not found in {file_name}.\n"
            f"The workshop TODO block this update targets is missing or has changed:\n"
            f"---\n{str_to_find}\n---"
        )
    if count > 1:
        raise SystemExit(
            f"ERROR: search string appears {count} times in {file_name}; expected exactly one."
        )

    with open(file_name, "w") as fh:
        fh.write(txt.replace(str_to_find, replacement_str))
