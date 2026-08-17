# libpq (psql / pg_dump) は keg-only なので PATH に追加する。
# typeset -U で再 source 時の重複を防ぐ。
typeset -U path PATH
path=(/opt/homebrew/opt/libpq/bin $path)

# Fargate の踏み台タスク(ECS Exec 有効)経由で Aurora への TCP トンネルを張る。
# アカウント ID / クラスタ名 / エンドポイントはこのリポジトリが public のため引数で渡す。
aurora-tunnel() {
  emulate -L zsh

  local profile="$1" cluster="$2" service="$3" host="$4" local_port="${5:-15432}"
  if [[ -z "$profile" || -z "$cluster" || -z "$service" || -z "$host" ]]; then
    print -u2 "usage: aurora-tunnel <aws-profile> <ecs-cluster> <ecs-service> <db-endpoint> [local-port]"
    return 1
  fi

  local task_arn task_id runtime_id
  task_arn="$(aws ecs list-tasks --profile "$profile" --cluster "$cluster" \
    --service-name "$service" --desired-status RUNNING \
    --query 'taskArns[0]' --output text)" || return
  if [[ -z "$task_arn" || "$task_arn" == "None" ]]; then
    print -u2 "aurora-tunnel: RUNNING なタスクが ${cluster}/${service} に見つかりません"
    return 1
  fi

  task_id="${task_arn##*/}"
  runtime_id="$(aws ecs describe-tasks --profile "$profile" --cluster "$cluster" \
    --tasks "$task_arn" --query 'tasks[0].containers[0].runtimeId' --output text)" || return
  if [[ -z "$runtime_id" || "$runtime_id" == "None" ]]; then
    print -u2 "aurora-tunnel: runtimeId が取れません (ECS Exec が有効か確認してください)"
    return 1
  fi

  print -u2 "aurora-tunnel: ${host}:5432 -> localhost:${local_port} (task ${task_id})"
  aws ssm start-session --profile "$profile" \
    --target "ecs:${cluster}_${task_id}_${runtime_id}" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"${host}\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"${local_port}\"]}"
}
