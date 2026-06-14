{ pkgs }:
pkgs.writeShellScriptBin "record-status" ''
  pid=`${pkgs.procps}/bin/pgrep -f 'gpu-screen-recorder.*Videos/record'`
  status=$?

  if [ $status != 0 ]
  then
    echo '';
  else
    echo '';
  fi;
''
