# Agent 指引

這些指引適用於整個 `gitops-demo-argocd` repository。編輯程式碼、Terraform、GitHub Actions、腳本或文件時都必須遵循。

## Repository 範圍

- 本 repository 管理平台與 GitOps 層：安裝 ArgoCD、ArgoCD 自我管理、註冊 Worker Cluster，以及初始化根 Application。
- Kubernetes 叢集佈建由 `gitops-demo-cluster` 負責，不屬於本 repository。
- Shared OpenVPN建立於獨立Linode VM，由`gitops-demo-openvpn-dns`負責；不在Kubernetes Cluster內建立，本repository也不取得其producer或BASE configuration ownership。
- Application manifest 與 ApplicationSet 由 `gitops-demo-apps` 負責，不屬於本 repository。
- frontend / backend 原始碼、Dockerfile 與映像建置 workflow 分別由 `gitops-demo-frontend`、`gitops-demo-backend` 負責，不屬於本 repository。
- apps repository 名稱為 `gitops-demo-apps`；根 Application 與 apps repo ApplicationSet 的 `repoURL` 必須使用 `https://github.com/KittyChen913/gitops-demo-apps.git`。
- 預設分支是 `master`，不是 `main`。

## 目錄結構

- `terraform/argocd/<environment>/install/`：ArgoCD 安裝（namespace、p0/p1/p2、Worker Cluster Secret）的獨立 Terraform root 與 state。
- `terraform/argocd/<environment>/self-manage/`：ArgoCD self-managed Application 的獨立 Terraform root 與 state。
- `terraform/argocd/<environment>/ateam/`：ATeam Root Application 的獨立 Terraform root 與 state。
- `terraform/argocd/<environment>/private-network/`：Dev／Prod private entry 的獨立 Terraform root 與 state。
- `terraform/argocd/environments/`：dev 與 prod 各自的共用 environment config，供 Terraform 與 GitHub Actions 讀取。
- `argocd/install/`：安裝 ArgoCD 的 Kustomize manifest。
- `argocd/bootstrap/`：ArgoCD 自我管理與根 Application manifest。
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
- README 與 docs 使用繁體中文敘述，並遵守相同的專有名詞大小寫。
- Workflow／job／step、composite action 的 `name` 與 `description` 必須使用英文。
- 程式碼內的文字必須使用英文，包括 Terraform `description`／`error_message`、CLI／UI 文字、log、error、warning、summary 與其他執行訊息；但等待／重試迴圈中即時印給人類觀察進度的狀態訊息（例如第幾次嘗試、剩餘秒數、失敗原因、逾時後的診斷輸出）例外，使用繁體中文。
- 產品名稱的唯一允許拼法為 `ArgoCD`。
- 自動生成檔案（例如 `.terraform.lock.hcl`）的生成器註解、shebang、lint directive 與被註解掉的程式碼不需翻譯或改寫。

## Terraform 規則

- 不得在 provider block 中寫死 AWS region，必須使用 `var.aws_region`。
- 不得將 AWS region 儲存為 GitHub variable。Workflow 應沿用 `.github/actions/configure-aws-credentials` 的預設 OIDC region `ap-southeast-1`。
- SSM path prefix、Management/Worker Cluster labels、Root Application metadata 與 private network 非機密設定必須定義於 `terraform/argocd/environments/<environment>.json`，不得在 Terraform root、GitHub Variables 或 workflow 重複寫死。
- dev 與 prod 必須使用獨立的 environment config；修改 prod 設定不得觸發 dev apply。
- Root Application 設定的 `name` 必須與對應 manifest 的 `metadata.name` 一致。
- `terraform/argocd/<environment>/{install,self-manage,ateam,private-network}/backend.tf` 必須包含完整靜態 S3 backend 設定：`bucket`、`region`、`key`、`encrypt` 與 `use_lockfile`。
- dev 與 prod 的 state key 必須分別為 `gitops-demo-argocd/<environment>/argocd-install/terraform.tfstate`、`gitops-demo-argocd/<environment>/argocd-self-manage/terraform.tfstate`、`gitops-demo-argocd/<environment>/argocd-ateam/terraform.tfstate`、`gitops-demo-argocd/<environment>/argocd-private-network/terraform.tfstate`。
- Terraform init 必須直接在 `terraform/argocd/<environment>/{install,self-manage,ateam,private-network}` 其中一個 root 執行，不得使用 `-backend-config` 動態注入 backend 值。
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
- Workflow 需要讀取 ArgoCD environment config 時，必須使用 `.github/actions/load-environment-config`，不得自行組合 config 路徑或重複以 `jq` 解析欄位。
- 使用目前的 action major tag：`actions/checkout@v6`、`hashicorp/setup-terraform@v4`、`actions/upload-artifact@v7`、`azure/setup-kubectl@v5` 與 `aws-actions/configure-aws-credentials@v6`。

## Workflow 職責

- `terraform-plan.yml` 是針對 `master` pull request 的 PR gate。
- `terraform-apply-dev.yml` 會在 push 至 `master` 或手動觸發時部署 dev。
- `terraform-apply-prod.yml` 會從 commit 可追溯至 `master` 的 SemVer tag 部署 prod；prod 必須依賴 GitHub Environment 核准。
- 本repository不保留跨環境的緊急手動 override apply workflow。Dev 的手動補跑走 `terraform-apply-dev.yml` 的 `workflow_dispatch`；prod 只能透過 SemVer tag 觸發，不提供手動補跑入口。
- 本repository不保留backend bootstrap workflow，也不建立、驗證或校正S3 State Bucket；bucket lifecycle與安全設定由repository外部owner負責。
- Apply workflow 必須將部署分成依序執行的三個 Terraform job：安裝 ArgoCD、註冊 ArgoCD self-managed Application、註冊 ATeam Root Application。
- `install`／`self-manage`／`ateam` 三個 ArgoCD Terraform job 各自使用自己獨立的 state（`terraform/argocd/<environment>/{install,self-manage,ateam}/`），透過 `_terraform-apply-stage.yml` 執行完整、不帶 `-target` 的 plan/apply；三者之間的順序由 workflow 的 `needs` 鏈保證，不使用 Terraform 跨 state 的 `depends_on`。`install` job 另對相同環境的 private-network state 執行完整、不帶 `-target` 的 plan/apply。
- `terraform-destroy.yml` 僅 `workflow_dispatch` 觸發，透過 `_terraform-destroy-stage.yml` 對 `terraform/argocd/<environment>/{install,self-manage,ateam,private-network}/` 四個獨立 state 執行完整、不帶 `-target` 的 `terraform destroy`；stage 順序與 apply 完全相反（`ateam` → `self-manage` → `private-network` → `install`），由 workflow 的 `needs` 鏈保證。`install` 必須排在最後，因為 `argocd` namespace 由該 root 擁有。
- 僅修改文件時，不應觸發部署 workflow。

跨Repository從零部署順序固定為：Cluster foundation → OpenVPN／DNS → Cluster worker firewall convergence → ArgoCD → User Provisioning。

## Workflow 安全規則

- 在 `run:` block 中，必須先將 `inputs.*`、`github.ref_name`、`github.actor`、`github.ref_type` 等可由使用者控制的 expression 移至 `env:`，再於 shell 中引用環境變數。
- Plan、apply 與 destroy log 必須過濾包含 token、secret 或 password 賦值的行。
- 若存在 `write_kubeconfig_files` 變數，CI 執行 Terraform 時必須設定 `TF_VAR_write_kubeconfig_files: "false"`。
- Provider token 與叢集 credentials 必須存放於 AWS SSM Parameter Store，不得存放於 GitHub Secrets。
- Workflow 需要取得共用 SSM provider token 時，必須使用 `.github/actions/get-ssm-parameters`。

## ArgoCD 與 GitOps

- Terraform 從 `argocd/install/` 安裝 ArgoCD，並套用 `argocd/bootstrap/` 中的 bootstrap manifest。
- 根 Application manifest 位於 `argocd/bootstrap/<team>/`。
- Management Cluster 只運行 ArgoCD；Worker Cluster 運行應用程式 workload。
- 不得將 application layer manifest 加入本 repository。
- 除非 workflow 明確用於驗證或緊急處理，否則不得為 Terraform 已處理的 bootstrap 行為手動加入 `kubectl apply` 步驟。

## 安全與破壞性操作

- 不要主動執行 `terraform apply`／`terraform destroy`，或手動觸發 `terraform-apply-dev.yml`、`terraform-apply-prod.yml`、`terraform-apply.yml`、`terraform-destroy.yml` 等會改變雲端／ArgoCD 狀態的命令，除非使用者明確要求。
- `terraform-destroy.yml` 僅 `workflow_dispatch` 觸發，destroy 選定環境 apply 建立的四個 root（`ateam`／`self-manage`／`private-network`／`install`，與 apply 完全相反的順序），依使用者要求不含任何額外確認步驟；如需移除已建立的 ArgoCD 或 private network 資源，仍須先與使用者確認範圍與方式，不得自行觸發此 workflow 或以其他等效手段執行 `terraform destroy`。
- `private-network` root 不得再加回 `lifecycle.prevent_destroy`：該設定只接受 literal 值，無法以 variable 開關，加回會讓 `terraform-destroy.yml` 無法執行。Apply path 的刪除保護由 `terraform-plan.yml` 與 `_terraform-apply-stage.yml` 的「Reject … delete or replacement」plan guard 負責，修改這些 root 時不得移除該 guard。
- Destroy `private-network` 會移除 `/gitops/<environment>/platform/argocd/ENDPOINT_IP` 與 `ENDPOINT_HOSTNAME` 這兩個供 `gitops-demo-openvpn-dns` 讀取的 contract parameters；該 root 同時讀取 OpenVPN／DNS 發布的 `INTERNAL_DOMAIN` 與 `VPN_PUBLIC_EGRESS_IP`。因此 teardown 順序必須與部署順序相反，ArgoCD 必須在 OpenVPN／DNS 之前 destroy。
- 不要讀取、印出或提交 secret；若需確認 secret 是否存在，只回報存在與否。
- 不要修改 Terraform state、遠端 S3 state 或 GitHub Environment protection 設定，除非使用者明確要求。
- 不要回復使用者既有未提交變更；工作區已有變更時，先理解並在其上工作。

## 腳本與部署命令

- Shell 腳本必須通過 ShellCheck。
- Terraform init、plan 與 apply 必須透過 GitHub Actions 執行，不得加入本機部署 helper。
- Health 腳本與 verification workflow 不得輸出 token、CA data 或 kubeconfig 內容。

## 文件同步

- 修改 workflow、trigger、SSM path、GitHub Environment 要求、backend 行為或手動命令時，必須同步更新 `docs/ci-cd.md`。
- 修改必要 secret、variable、IAM permission 或 OIDC 設定時，必須同步更新 `docs/ci-secrets.md`。
- README 中的範例必須與 `docs/ci-cd.md` 保持一致。
- 分支相關的 workflow 設定、註解與文件都必須使用 `master`。

## 最小必要 Validation

- 依全域「最小必要 Validation」規範，先判定本次變更影響的 workflow、Shell execution path、Terraform root／module、Kustomize render target 或 shared configuration contract，再從 repository 既有的 `actionlint`、ShellCheck、Terraform fmt／validate、Kustomize build 與 contract checks 中選擇能直接驗證風險的最小子集。
- 只影響單一環境、root、script 或 manifest target 時，優先使用對應的 targeted validation；不得預設檢查 dev、prod、所有 workflows、所有 scripts 或完整 repository。
- 共用 module、environment config schema、reusable workflow、composite action 或 ArgoCD bootstrap contract 確實影響多個直接 consumers 時，才擴大驗證範圍，並在執行前說明局部驗證不足的原因。
- 完整 workflow quality、Terraform plan、apply 與 runtime verification 屬 PR、merge、release、deployment 或獨立驗收 gate，不是每次本機局部修改後的預設 validation。
- dependencies、backend、credentials、Container Image 或安全執行條件不可用時，標示 `BLOCKED` 或 `NOT RUN`，並說明替代靜態驗證與未取得的信心。
