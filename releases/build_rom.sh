#!/bin/bash

exit_with_error() {
  echo -e "\nERROR:\n${1}\n"
  
  exit 1
}

check_dependencies() {
  if [[ $OSTYPE == darwin* ]]; then
    for j in unzip md5 shasum cat cut getopt; do
      command -v ${j} > /dev/null 2>&1 || exit_with_error "This script requires\n${j}"
    done
    md5command="md5 -r"
    shacommand="shasum"
  else
    for j in unzip md5sum sha1sum cat cut getopt; do
      command -v ${j} > /dev/null 2>&1 || exit_with_error "This script requires\n${j}"
    done
    md5command="md5sum"
    shacommand="sha1sum"
  fi
}

check_permissions () {
  if [ ! -w ${BASEDIR} ]; then
    exit_with_error "Cannot write to\n${BASEDIR}"
  fi
}

read_ini () {
  if [ ! -f ${BASEDIR}/build_rom.ini ]; then
    exit_with_error "Missing build_rom.ini"
  else
    source ${BASEDIR}/build_rom.ini
  fi
}

uncompress_zips() {
  if [ ! -n "${zips}" ]; then
    zips=(${zip})
  fi
  tmpdir=tmp.`date +%Y%m%d%H%M%S%s`
  for tzip in "${zips[@]}"; do
    if [ -f ${BASEDIR}/${tzip} ]; then
        unzippedfiles+=($(unzip -Z -1 "${BASEDIR}/${tzip}"))
        if [ $? != 0 ] ; then
          exit_with_error "Something went wrong\nwhen listing\n${tzip}\nAborting."
        fi
        unzip -qq -d ${BASEDIR}/${tmpdir}/ ${BASEDIR}/${tzip}
        if [ $? != 0 ] ; then
          delete_tmpdir
          exit_with_error "Something went wrong\nwhen extracting\n${tzip}\nAborting."
        fi
      else
        echo -e "${tzip} not found.\nSkipping."
      fi
  done
  if [ -z "${unzippedfiles[*]}" ]; then
    delete_tmpdir
    exit_with_error "No files unzipped."
  fi
}

generate_md5_links() {
  for rom in "${unzippedfiles[@]}"; do
    filepath=${BASEDIR}/${tmpdir}/${rom}
    filemd5=$(${md5command} ${filepath}|cut -f 1 -d " ")
    ln -s "${rom}" "${BASEDIR}/${tmpdir}/md5.${filemd5}"
#    ln "${filepath}" "${BASEDIR}/${tmpdir}/md5.${filemd5}"
  done
#  ls -l ${BASEDIR}/${tmpdir}/md5*
}

generate_sha1_links() {
  for rom in "${unzippedfiles[@]}"; do
    filepath=${BASEDIR}/${tmpdir}/${rom}
    filesha=$(${shacommand} -b ${filepath} | cut -d " " -f 1)
    ln -s "${rom}" "${BASEDIR}/${tmpdir}/sha1.${filesha}"
#    ln "${filepath}" "${BASEDIR}/${tmpdir}/sha1.${filesha}"
  done
#  ls -l ${BASEDIR}/${tmpdir}/sha1*
}

select_roms() {
  if [ "${USESHA1S}" -a "${ishas}" ]; then
    for i in "${ishas[@]}" ; do
      ROMFILELIST+=("sha1.${i}")
    done
  elif [ "${USEMD5S}" -a "${imd5s}" ]; then
    for i in "${imd5s[@]}" ; do
      ROMFILELIST+=("md5.${i}")
    done
  elif [ "${USEFILENAMES}" ]; then
    ROMFILELIST=("${ifiles[@]}") ## copy ifiles array
  fi
}

generate_output_rom() {
  for romfile in "${ROMFILELIST[@]}" ; do
    if [ ! -f "${BASEDIR}/${tmpdir}/${romfile}" ]; then
      delete_tmpdir
      exit_with_error "ROM with name/sum ${romfile} does not exist"
    else
      cat "${BASEDIR}/${tmpdir}/${romfile}" >> "${BASEDIR}/${tmpdir}/${ofile}"
    fi
  done
}

validate_output_rom() {
  ofileMd5sumCurrent=$(${md5command} ${BASEDIR}/${tmpdir}/${ofile}|cut -f 1 -d " ")

  if [ "${ofileMd5sumValid}" -a \( "${ofileMd5sumValid}" != "${ofileMd5sumCurrent}" \) ]; then
    echo -e "\nExpected md5:\n${ofileMd5sumValid}"
    echo -e "Actual md5:\n${ofileMd5sumCurrent}"
    mv ${BASEDIR}/${tmpdir}/${ofile} .
    delete_tmpdir
    exit_with_error "Generated ${ofile}\nis invalid.\nThis is more likely\ndue to incorrect\n${zip} content."
  else
    mv ${BASEDIR}/${tmpdir}/${ofile} ${BASEDIR}/.
    if [ -n "${ofileMd5sumValid}" ]; then
      echo -e "\nChecksum verification passed.\n"
    else
      echo -e "\nNo checksum provided.\n"
    fi
    echo -e "Copy file ${ofile}\ninto root of SD card\nalong with the rbf file.\n"
  fi
}

output_selected_rom_sums() {
  if [ -z "${imd5s[*]}" -o ! "${USEMD5S}" ]; then
  ## generate md5s
    unset imd5s ; declare -a imd5s
    for file in "${ROMFILELIST[@]}"; do
      if [[ $OSTYPE == darwin* ]]; then
        imd5s+=$(md5 -r ${BASEDIR}/${tmpdir}/${file}|cut -f 1 -d " ")
      else
        imd5s+=$(md5sum ${BASEDIR}/${tmpdir}/${file}|cut -f 1 -d " ")
      fi
    done
  fi
  echo imd5s=\(${imd5s[*]}\)
  if [ -z "${ishas[*]}" -o ! "${USESHA1S}" ]; then
  ## generate sha1s
    unset ishas ; declare -a ishas
    for file in "${ROMFILELIST[@]}"; do
      if [[ $OSTYPE == darwin* ]]; then
        ishas+=($(shasum ${BASEDIR}/${tmpdir}/${file}|cut -f 1 -d " "))
      else
        ishas+=($(sha1sum ${BASEDIR}/${tmpdir}/${file}|cut -f 1 -d " "))
      fi
    done
  fi
  echo ishas=\(${ishas[*]}\)
}

delete_tmpdir() {
  rm -rf "${BASEDIR}/${tmpdir}"
}

BASEDIR=$(dirname "$0")
USEFILENAMES=
USEMD5S=
USESHA1S=
PRINTROMSUMS=
declare -a ROMFILELIST
declare -a unzippedfiles

usage() {
  echo "Usage: $0 [-h][-f][-1][-p]" 1>&2
  echo "       -h print this help and exit" 1>&2
  echo "       -f use filenames to find ROMs" 1>&2
  echo "       -1 use sha1 hashes to find ROMs" 1>&2
  echo "       -5 use md5 hashes to find ROMs" 1>&2
  echo "       -p print md5 and sha1 hashes of ROMs used" 1>&2
  echo "Default is to use md5 hashes to find ROMs." 1>&2
  echo "If md5 hashes are not present then use sha1 hashes." 1>&2
  echo "If no input file hashes are present then use md5 hashes." 1>&2
  exit 1;
}

## verify dependencies
check_dependencies

args=`getopt hf15p $*`
if [ $? != 0 ]; then
    usage
fi
set -- $args

for i do
  case "$i" in
    -h)
      usage
      shift;;
    -f)
      USEFILENAMES=1
      shift;;
    -1)
      ## use SHA1 to find the ROMs (also the default if SHA1 hashes are provided)
      USESHA1S=1
      shift;;
    -5)
      ## use MD5 to find the ROMs (also the default if SHA1 hashes are provided but not MD5)
      USEMD5S=1
      shift;;
    -p)
      ## generate sums
      ## print the sums for the ROMs used
      ## this option is useful if do not know the sha1 or md5 hashes for the files
      ## and wish to generate them to put them in the config file.
      PRINTROMSUMS=1
      shift;;
    --)
      shift; break;;
  esac
done

## verify write permissions
check_permissions

## load ini
read_ini

if [ ! \( "${USEFILENAMES}" -o "${USESHA1S}" -o "${USEMD5S}" \) ]; then
## nothing passed, select a default
  if [ -n "${ishas[*]}" ]; then
    USESHA1S=1
  elif [ -n "${imd5s[*]}" ]; then
    USEMD5S=1
  else
    USEFILENAMES=1
  fi
fi

echo "Generating ROM ..."

## extract packages
uncompress_zips

## if using SHA1, generate SHA1 links from ROMs
if [ "${USESHA1S}" -o "${PRINTROMSUMS}" ]; then
  ## generate sha1 links from ROMs
  generate_sha1_links
fi
if [ "${USEMD5S}" -o "${PRINTROMSUMS}" ]; then
  ## generate md5 links from ROMs
  generate_md5_links
fi

## select roms using the chosen method
select_roms

## build output rom
generate_output_rom

## verify rom
validate_output_rom

## generate md5s from roms selected
if [ "${PRINTROMSUMS}" ]; then
    output_selected_rom_sums
fi

## delete the contents of the tmpdir
delete_tmpdir
