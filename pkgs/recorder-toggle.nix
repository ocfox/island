{ lib, pkgs }:
pkgs.writeShellScriptBin "screen-recorder-toggle" ''
  recorder='gpu-screen-recorder.*Videos/record'
  pid=`${pkgs.procps}/bin/pgrep -f "$recorder"`
  status=$?

  if [ $status != 0 ]
  then
    ${pkgs.coreutils}/bin/mkdir -p "$HOME/Videos/record"
    region="$(${lib.getExe pkgs.slurp} -f "%wx%h+%x+%y")"
    [ -n "$region" ] || exit 0
    # Desktop audio only. Add "|default_input" to mix the mic into the same
    # track, or a second -a flag to give it its own track.
    ${lib.getExe' pkgs.gpu-screen-recorder "gpu-screen-recorder"} \
      -w "$region" \
      -a default_output \
      -o "$HOME/Videos/record/$(date +'recording_%Y-%m-%d-%H%M%S.mp4')"
  else
    ${pkgs.procps}/bin/pkill --signal SIGINT -f "$recorder"
  fi;
''
