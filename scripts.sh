#!/bin/bash

tsr () {
  if [[ $# -eq 0 ]]; then
    cd $JJC_PROJECTS/trans-siberian-railroad
    return 0
  fi

  while getopts ":tdf" opt; do
    case $opt in
      t)
        echo "test!!"
        mix test --exclude not_implemented
        ;;
      d)
        mix dialyzer
        ;;
      f)
        mix format
        ;;
      \?)
        echo "Invalid option: -$OPTARG" >&2
        ;;
    esac
  done
}
