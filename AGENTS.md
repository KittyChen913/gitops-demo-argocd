# Agent 指引

這些指引適用於整個 `gitops-demo-infra` repository。編輯程式碼、Terraform、GitHub Actions、腳本或文件時都必須遵循。

## Repository 範圍

- 本 repository 管理平台與 GitOps 層：安裝 Argo CD、Argo CD 自我管理、註冊 Worker Cluster，以及初始化根 Application。
- Kubernetes 叢集佈建由 `gitops-demo-cluster` 負責，不屬於本 repository。
- Shared OpenVPN建立於獨立Linode VM，由`gitops-demo-platform-access`負責；不在Kubernetes Cluster內建立，本repository也不取得其producer或BASE configuration ownership。
- Application manifest 與 ApplicationSet 由 `gitops-demo-apps` 負責，不屬於本 repository。
- frontend / backend 原始碼、Dockerfile 與映像建置 workflow 分別由 `gitops-demo-frontend`、`gitops-demo-backend` 負責，不屬於本 repository。
- apps repository 名稱為 `gitops-demo-apps`；根 Application 與 apps repo ApplicationSet 的 `repoURL` 必須使用 `https://github.com/KittyChen913/gitops-demo-apps.git`。
- 預設分支是 `master`，不是 `main`。

## 目錄結構

- `terraform/argocd/dev/`：dev 環境的正式 Terraform root，包含靜態 backend，並讀取 dev environment config。
- `terraform/argocd/prod/`：prod 環境的正式 Terraform root，包含靜態 backend，並讀取 prod environment config。
- `terraform/argocd/environments/`：dev 與 prod 各自的共用 environment config，供 Terraform 與 GitHub Actions 讀取。
- `terraform/modules/argocd/`：dev 與 prod 共用的 Argo CD Terraform module。
- `argocd/install/`：安裝 Argo CD 的 Kustomize manifest。
- `argocd/bootstrap/`：Argo CD 自我管理與根 Application manifest。
- `.github/actions/`：本地 composite action。
- `.github/workflows/`：GitHub Actions workflow。
- `scripts/`：CI 輔助腳本。
- `docs/`：CI/CD 與設定文件。

## 註解撰寫規範

- 人工維護的程式碼、Terraform、GitHub Actions、腳本、manifest 與設定檔註解必須使用繁體中文。
- 專有名詞、產品名稱、API、資源種類、欄位名稱、命令、路徑、識別字與無適當中文譯名的技術術語可保留英文。
- 不得以完整英文句子撰寫註解；英文專有名詞應放在中文敘述中。
- `Management Cluster`、`Worker Cluster`、`Cluster` 與 `S3 State Bucket` 均視為專有名詞，不得翻譯成中文，也不得使用其他大小寫變體。
- 複數形式必須寫成 `Management Clusters`、`Worker Clusters` 與 `S3 State Buckets`。
- README、docs、Terraform description、workflow 顯示文字、summary 與人工維護的執行訊息也必須遵守相同的專有名詞大小寫。
- 自動生成檔案（例如 `.terraform.lock.hcl`）的生成器註解、shebang、lint directive 與被註解掉的程式碼不需翻譯或改寫。

## Terraform 規則

- 不得在 provider block 中寫死 AWS region，必須使用 `var.aws_region`。
- 不得將 AWS region 儲存為 GitHub variable。Workflow 應沿用 `.github/actions/configure-aws-credentials` 的預設 OIDC region `ap-southeast-1`。
- SSM path prefix、Management/Worker Cluster labels、Root Application metadata 與 private network 非機密設定必須定義於 `terraform/argocd/environments/<environment>.json`，不得在 Terraform root、GitHub Variables 或 workflow 重複寫死。
- dev 與 prod 必須使用獨立的 environment config；修改 prod 設定不得觸發 dev apply。
- Root Application 設定的 `name` 必須與對應 manifest 的 `metadata.name` 一致。
- `terraform/argocd/<environment>/backend.tf` 必須包含完整靜態 S3 backend 設定：`bucket`、`region`、`key`、`encrypt` 與 `use_lockfile`。
- dev 與 prod state key 必須分別為 `gitops-demo-infra/dev/argocd/terraform.tfstate` 與 `gitops-demo-infra/prod/argocd/terraform.tfstate`。
- Terraform init 必須直接在 `terraform/argocd/dev` 或 `terraform/argocd/prod` 執行，不得使用 `-backend-config` 動態注入 backend 值。
- S3 State Bucket 必須由 repository 外部流程預先建立；本 repository 的 workflow 與 OIDC role 不得要求或使用 `s3:CreateBucket`。
- Terraform state、plan、kubeconfig 與 `terraform.tfvars` 都不得提交。

## CI/CD 與 GitHub Actions

- GitHub Actions 的 AWS 驗證只能使用 OIDC。
- 不得使用、宣告或傳遞 `secrets.AWS_ACCESS_KEY_ID` 或 `secrets.AWS_SECRET_ACCESS_KEY`。
- 必須透過 `.github/actions/configure-aws-credentials` 設定 AWS credentials；workflow 不得直接呼叫 `aws-actions/configure-aws-credentials`。
- `AWS_ACCOUNT_ID` 必須儲存為 GitHub Repository Secret，並以 `secrets.AWS_ACCOUNT_ID` 引用。
- GitHub Environment 只用於 dev/prod deployment protection 與 deployment history，不得保存 Terraform input、一般設定或 `AWS_ACCOUNT_ID`。
- 需要 AWS 的 job 必須包含 `permissions: id-token: write` 與 `contents: read`。
- 只有 job 透過 `uses: ./.github/workflows/...` 呼叫 reusable workflow 時才需要 `secrets: inherit`；composite action 不使用此設定。
- 修改 composite action 時，必須透過 `.github/actions/**` 將變更納入相關 workflow 的 `paths` filter。
- Workflow 需要讀取 Argo CD environment config 時，必須使用 `.github/actions/load-environment-config`，不得自行組合 config 路徑或重複以 `jq` 解析欄位。
- 使用目前的 action major tag：`actions/checkout@v6`、`hashicorp/setup-terraform@v4`、`actions/upload-artifact@v7`、`azure/setup-kubectl@v5` 與 `aws-actions/configure-aws-credentials@v6`。

## Workflow 職責

- `terraform-plan.yml` 是針對 `master` pull request 的 PR gate。
- `terraform-apply-dev.yml` 會在 push 至 `master` 或手動觸發時部署 dev。
- `terraform-apply-prod.yml` 會從 commit 可追溯至 `master` 的 SemVer tag 部署 prod；prod 必須依賴 GitHub Environment 核准。
- `terraform-apply.yml` 僅供手動 override 使用。
- 本repository不保留backend bootstrap workflow，也不建立、驗證或校正S3 State Bucket；bucket lifecycle與安全設定由repository外部owner負責。
- Apply workflow 必須將部署分成依序執行的三個 Terraform job：安裝 Argo CD、註冊 Argo CD self-managed Application、註冊 ATeam Root Application。
- 三個 Argo CD Terraform job 必須使用相同環境的遠端 state，並透過 `_terraform-apply-stage.yml` 執行對應的 targeted plan/apply。
- 僅修改文件時，不應觸發部署 workflow。

跨Repository從零部署順序固定為：Cluster foundation → Platform Access → Cluster worker firewall convergence → Infra / Argo CD → User Provisioning。

## Workflow 安全規則

- 在 `run:` block 中，必須先將 `inputs.*`、`github.ref_name`、`github.actor`、`github.ref_type` 等可由使用者控制的 expression 移至 `env:`，再於 shell 中引用環境變數。
- Plan、apply 與 destroy log 必須過濾包含 token、secret 或 password 賦值的行。
- 若存在 `write_kubeconfig_files` 變數，CI 執行 Terraform 時必須設定 `TF_VAR_write_kubeconfig_files: "false"`。
- Provider token 與叢集 credentials 必須存放於 AWS SSM Parameter Store，不得存放於 GitHub Secrets。
- Workflow 需要取得共用 SSM provider token 時，必須使用 `.github/actions/get-ssm-parameters`。

## Argo CD 與 GitOps

- Terraform 從 `argocd/install/` 安裝 Argo CD，並套用 `argocd/bootstrap/` 中的 bootstrap manifest。
- 根 Application manifest 位於 `argocd/bootstrap/<team>/`。
- Management Cluster 只運行 Argo CD；Worker Cluster 運行應用程式 workload。
- 不得將 application layer manifest 加入本 repository。
- 除非 workflow 明確用於驗證或緊急處理，否則不得為 Terraform 已處理的 bootstrap 行為手動加入 `kubectl apply` 步驟。

## 腳本與部署命令

- Shell 腳本必須通過 ShellCheck。
- Terraform init、plan 與 apply 必須透過 GitHub Actions 執行，不得加入本機部署 helper。
- Health 腳本與 verification workflow 不得輸出 token、CA data 或 kubeconfig 內容。

## 文件同步

- 修改 workflow、trigger、SSM path、GitHub Environment 要求、backend 行為或手動命令時，必須同步更新 `docs/ci-cd.md`。
- 修改必要 secret、variable、IAM permission 或 OIDC 設定時，必須同步更新 `docs/ci-secrets.md`。
- README 中的範例必須與 `docs/ci-cd.md` 保持一致。
- 分支相關的 workflow 設定、註解與文件都必須使用 `master`。

## 驗證

- 修改 workflow 時，應盡可能執行 actionlint：
  `docker run --rm -v "${PWD}:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color`
- 修改腳本時，應盡可能執行 ShellCheck：
  `docker run --rm --entrypoint shellcheck -v "${PWD}:/repo" --workdir /repo rhysd/actionlint:1.7.12 scripts/argocd-runtime-health.sh`
- 修改 Terraform 時，若 dependencies 與 backend 均可使用，應在相關 Terraform root 執行 `terraform fmt` 與 `terraform validate`。
