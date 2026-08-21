# libpq (psql / pg_dump) は keg-only なので PATH に追加する。
# typeset -U で再 source 時の重複を防ぐ。
typeset -U path PATH
path=(/opt/homebrew/opt/libpq/bin $path)

# aurora-tunnel は .local/bin/aurora-tunnel (PATH 上の実行可能スクリプト) を参照。
# opr <env-name> -- aurora-tunnel ... の形で op run のサブプロセスから呼び出すため、
# シェル関数ではなく PATH 上のスクリプトとして提供している。
