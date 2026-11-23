# Portable archive extraction helper. The lazy wrapper in modules/lazy-tools.zsh
# sources this file in the parent shell on first use.

extract() {
  setopt localoptions noautopushd

  {
    local remove_archive=0
    local target_directory=''
    local extract_status=0

    function _mpz_extract_safe_member_name() {
      local member="$1"
      local component

      [[ "$member" != /* ]] || return 1
      for component in ${(s:/:)member}; do
        [[ "$component" != .. ]] || return 1
      done
      return 0
    }

    function _mpz_extract_validate_name_list() {
      local listing="$1"
      local member

      while IFS= read -r member; do
        _mpz_extract_safe_member_name "$member" || return 1
      done < "$listing"
      return 0
    }

    function _mpz_extract_validate_tar() {
      local archive="$1"
      local staging="$2"
      local listing="$staging/tar.list"
      local verbose="$staging/tar.verbose"
      local entry

      if (( $+commands[tar] )); then
        if tar --no-absolute-names --version >/dev/null 2>&1; then
          env -u TAR_OPTIONS -u TAR -u GZIP -u BZIP2 -u XZ -u ZSTD \
            tar --no-absolute-names -tf "$archive" > "$listing" 2>/dev/null || return 1
          env -u TAR_OPTIONS -u TAR -u GZIP -u BZIP2 -u XZ -u ZSTD \
            tar --no-absolute-names -tvf "$archive" > "$verbose" 2>/dev/null || return 1
        else
          env -u TAR_OPTIONS -u TAR -u GZIP -u BZIP2 -u XZ -u ZSTD \
            tar -tf "$archive" > "$listing" 2>/dev/null || return 1
          env -u TAR_OPTIONS -u TAR -u GZIP -u BZIP2 -u XZ -u ZSTD \
            tar -tvf "$archive" > "$verbose" 2>/dev/null || return 1
        fi
      else
        return 1
      fi

      _mpz_extract_validate_name_list "$listing" || return 1
      while IFS= read -r entry; do
        case "$entry" in
          -*|d*) ;;
          *) return 1 ;;
        esac
      done < "$verbose"
      return 0
    }

    function _mpz_extract_validate_zip() {
      local archive="$1"
      local staging="$2"
      local listing="$staging/zip.list"
      local verbose="$staging/zip.verbose"
      local entry

      (( $+commands[zipinfo] && $+commands[unzip] )) || return 1
      env -u ZIP_OPTIONS -u UNZIP_OPTIONS \
        zipinfo -1 "$archive" > "$listing" 2>/dev/null || return 1
      env -u ZIP_OPTIONS -u UNZIP_OPTIONS \
        zipinfo -l "$archive" > "$verbose" 2>/dev/null || return 1
      _mpz_extract_validate_name_list "$listing" || return 1
      while IFS= read -r entry; do
        case "$entry" in
          -*|d*) ;;
          l*|b*|c*|p*|s*) return 1 ;;
          *) continue ;;
        esac
      done < "$verbose"
      return 0
    }

    function _mpz_extract_validate_tree() {
      local tree="$1"
      local unsafe

      unsafe=$(find "$tree" -type l -print -quit 2>/dev/null) || return 1
      [[ -z "$unsafe" ]] || return 1
      unsafe=$(find "$tree" ! -type f ! -type d -print -quit 2>/dev/null) || return 1
      [[ -z "$unsafe" ]] || return 1
      return 0
    }

    function _mpz_extract_tar() {
      local archive="$1"
      local tree="$2"

      if tar --no-absolute-names --version >/dev/null 2>&1; then
        env -u TAR_OPTIONS -u TAR -u GZIP -u BZIP2 -u XZ -u ZSTD \
          tar --no-absolute-names --no-same-owner --no-same-permissions \
          -xf "$archive" -C "$tree" 2>/dev/null
      else
        env -u TAR_OPTIONS -u TAR -u GZIP -u BZIP2 -u XZ -u ZSTD \
          tar -xf "$archive" -C "$tree" 2>/dev/null
      fi
    }

    function _mpz_extract_zip() {
      local archive="$1"
      local tree="$2"

      env -u ZIP_OPTIONS -u UNZIP_OPTIONS \
        unzip -q "$archive" -d "$tree" 2>/dev/null
    }

    function _mpz_extract_decompress() {
      local kind="$1"
      local archive="$2"
      local destination="$3"

      case "$kind" in
        gz)
          env -u GZIP gzip -cd -- "$archive" > "$destination" 2>/dev/null
          ;;
        bz2)
          env -u BZIP2 bzip2 -cd -- "$archive" > "$destination" 2>/dev/null
          ;;
        xz)
          env -u XZ xz -cd -- "$archive" > "$destination" 2>/dev/null
          ;;
        zst)
          env -u ZSTD zstd -cd -- "$archive" > "$destination" 2>/dev/null
          ;;
        *)
          return 1
          ;;
      esac
    }

    while (( $# > 0 )); do
      case "$1" in
        -r|--remove)
          remove_archive=1
          shift
          ;;
        -t|--to-directory)
          shift
          if (( $# == 0 )); then
            print -u2 -- 'extract: --to-directory requires a directory'
            return 1
          fi
          target_directory="$1"
          shift
          if [[ ! -d "$target_directory" ]]; then
            print -u2 -- "extract: '$target_directory' is not a directory"
            return 1
          fi
          ;;
        --)
          shift
          break
          ;;
        *)
          break
          ;;
      esac
    done

    if (( $# == 0 )); then
      print -u2 -- 'Usage: extract [-r] [-t directory] archive...'
      return 1
    fi

    local original_pwd="$PWD"
    local file full_path basename stem target_root staging tree archive_copy
    local extract_dir suffix result kind

    target_root="${target_directory:-$PWD}"
    target_root="${target_root:A}"
    if [[ ! -d "$target_root" || ! -w "$target_root" ]]; then
      print -u2 -- "extract: '$target_root' is not a writable directory"
      return 1
    fi

    for file in "$@"; do
      if [[ ! -f "$file" ]]; then
        print -u2 -- "extract: '$file' is not a file"
        extract_status=1
        continue
      fi

      full_path="${file:A}"
      basename="${file:t}"
      stem="${basename%.*}"
      case "$basename" in
        *.tar.*) stem="${basename%%.tar.*}" ;;
        *.tgz) stem="${basename%.tgz}" ;;
        *.tbz|*.tbz2) stem="${basename%%.tbz*}" ;;
        *.txz) stem="${basename%.txz}" ;;
        *.tzst) stem="${basename%.tzst}" ;;
      esac

      staging=$(mktemp -d "$target_root/.mpz-extract.XXXXXX") || {
        print -u2 -- "extract: cannot create a private staging directory in '$target_root'"
        extract_status=1
        continue
      }
      chmod 700 "$staging"
      tree="$staging/tree"
      archive_copy="$staging/archive"
      mkdir -p "$tree"
      chmod 700 "$tree"

      if ! cp -p -- "$full_path" "$archive_copy"; then
        print -u2 -- "extract: cannot stage '$file'"
        rm -rf -- "$staging"
        extract_status=1
        continue
      fi
      chmod 600 "$archive_copy"

      result=1
      case "${basename:l}" in
        *.tar.gz|*.tgz|*.tar.bz2|*.tbz|*.tbz2|*.tar.xz|*.txz|*.tar.zst|*.tzst|*.tar)
          if _mpz_extract_validate_tar "$archive_copy" "$staging" && \
            _mpz_extract_tar "$archive_copy" "$tree" && \
            _mpz_extract_validate_tree "$tree"; then
            result=0
          fi
          ;;
        *.zip|*.jar|*.war|*.ear|*.whl|*.vsix|*.apk|*.aar|*.xpi)
          if _mpz_extract_validate_zip "$archive_copy" "$staging" && \
            _mpz_extract_zip "$archive_copy" "$tree" && \
            _mpz_extract_validate_tree "$tree"; then
            result=0
          fi
          ;;
        *.gz)
          if _mpz_extract_decompress gz "$archive_copy" \
            "$tree/${basename%.gz}" && _mpz_extract_validate_tree "$tree"; then
            result=0
          fi
          ;;
        *.bz2)
          if _mpz_extract_decompress bz2 "$archive_copy" \
            "$tree/${basename%.bz2}" && _mpz_extract_validate_tree "$tree"; then
            result=0
          fi
          ;;
        *.xz)
          if _mpz_extract_decompress xz "$archive_copy" \
            "$tree/${basename%.xz}" && _mpz_extract_validate_tree "$tree"; then
            result=0
          fi
          ;;
        *.zst)
          if _mpz_extract_decompress zst "$archive_copy" \
            "$tree/${basename%.zst}" && _mpz_extract_validate_tree "$tree"; then
            result=0
          fi
          ;;
        *)
          print -u2 -- "extract: '$file' is not a supported archive"
          ;;
      esac

      if (( result != 0 )); then
        print -u2 -- "extract: failed to extract '$file'"
        rm -rf -- "$staging"
        extract_status=1
        continue
      fi

      extract_dir="$target_root/$stem"
      suffix=1
      while [[ -e "$extract_dir" || -L "$extract_dir" ]]; do
        extract_dir="$target_root/$stem-$suffix"
        (( suffix++ ))
      done
      if ! mv -- "$tree" "$extract_dir"; then
        print -u2 -- "extract: cannot publish '$file'"
        rm -rf -- "$staging"
        extract_status=1
        continue
      fi
      rm -rf -- "$staging"

      if (( remove_archive )); then
        command rm -f -- "$full_path"
      fi
    done

    builtin cd -q -- "$original_pwd"
    return "$extract_status"
  } always {
    unfunction _mpz_extract_safe_member_name
    unfunction _mpz_extract_validate_name_list
    unfunction _mpz_extract_validate_tar
    unfunction _mpz_extract_validate_zip
    unfunction _mpz_extract_validate_tree
    unfunction _mpz_extract_tar
    unfunction _mpz_extract_zip
    unfunction _mpz_extract_decompress
  }
}
