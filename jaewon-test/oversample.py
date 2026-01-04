import numpy as np

def read_fbin(path: str) -> np.ndarray:
    with open(path, "rb") as f:
        n, d = np.fromfile(f, dtype=np.int32, count=2)   # 개수, 차원 읽기
        data = np.fromfile(f, dtype=np.float32, count=n*d)
    return data.reshape(n, d)

# 사용 예시
# X = read_fbin("/home/jaewonoh/workspace/ann-benchmark/jaewon-test/dataset/dbpedia_qwen_1024_1m.fbin")

import numpy as np, pandas as pd
import matplotlib.pyplot as plt
from numpy.linalg import norm
from typing import Dict, Tuple, Optional, List
from tqdm import tqdm


def binarize_sign(X: np.ndarray) -> np.ndarray:
    # {0,1} 로 부호 양자화 (Hamming 계산용)
    return (X >= 0).astype(np.uint8)

def fp_topk_indices(Xdb: np.ndarray, q: np.ndarray, K: int) -> np.ndarray:
    sims = Xdb @ q
    idx = np.argpartition(-sims, K-1)[:K]
    order = np.argsort(-sims[idx])
    return idx[order]

def recall_at_k(true_topk: np.ndarray, cand_sorted: np.ndarray, K: int) -> float:
    return len(set(true_topk).intersection(set(cand_sorted[:K]))) / K

# =========================
# 4) 핵심 실험 함수: 고정 K, α 변화
# =========================
def run_recall_curve_for_dataset(
        db_emb: np.ndarray,
        q_emb: np.ndarray,
        K: int,
        alphas: List[float],
        max_queries: Optional[int] = None,
        seed: int = 7
) -> pd.DataFrame:
    """
    db_emb: (N, d) 데이터 임베딩
    q_emb : (Q, d) 쿼리 임베딩
    K    : top-K (ground-truth 및 평가 K)
    alphas: oversampling 팩터 리스트 (예: [1.0,1.2,1.5,2.0,2.5,3.0])
    max_queries: Q가 크면 상한 지정 가능
    return: DataFrame [query_id, alpha, recall]
    """
    rng = np.random.default_rng(seed)

    # 정규화 (cosine 검색 전제)
    Xdb = l2_normalize(db_emb)
    Xq  = l2_normalize(q_emb)

    if max_queries is not None and Xq.shape[0] > max_queries:
        idx = rng.choice(Xq.shape[0], size=max_queries, replace=False)
        Xq = Xq[idx]
        q_map = {i:i for i in range(len(idx))}
    else:
        q_map = {i:i for i in range(Xq.shape[0])}

    # BQ (sign)
    Bdb = binarize_sign(Xdb)

    rows = []
    for qi, q in tqdm(enumerate(Xq)):
        sims = Xdb @ q
        # ground truth top-K
        true_idx = np.argpartition(-sims, K-1)[:K]
        true_idx = true_idx[np.argsort(-sims[true_idx])]

        # Hamming 거리 1회 계산
        bq = binarize_sign(q[None, :])[0]
        ham = (Bdb != bq).sum(axis=1)

        for a in alphas:
            M = int(np.ceil(a * K))
            # α·K by Hamming
            cand = np.argpartition(ham, M-1)[:M]
            # FP 재랭크
            order = np.argsort(-(sims[cand]))
            reranked = cand[order]
            rec = recall_at_k(true_idx, reranked, K)
            rows.append((qi, a, rec))

    return pd.DataFrame(rows, columns=["query_id", "alpha", "recall"])

def min_alpha_for_recall1(
        db_emb: np.ndarray,
        q_emb: np.ndarray,
        K: int,
        max_queries: Optional[int] = None,
        seed: int = 7,
) -> pd.DataFrame:
    """
    각 쿼리별로 recall@K = 1을 보장하는 최소 alpha(= M/K)를 계산.
    - 후보 선택은 '해밍 오름차순, 동률 시 FP(sim) 내림차순'으로 정렬해 누적 포함을 확인
      (너의 파이프라인: 해밍 상위 M 뽑고 → FP 재랭크와 일관되게 타이브레이크 적용)
    return: DataFrame [query_id, M_min, alpha_min]
    """
    rng = np.random.default_rng(seed)

    # 1) 정규화
    Xdb = l2_normalize(db_emb)
    Xq  = l2_normalize(q_emb)


    if max_queries is not None and Xq.shape[0] > max_queries:
        sel = rng.choice(Xq.shape[0], size=max_queries, replace=False)
        Xq = Xq[sel]

    # 2) BQ(sign)
    Bdb = binarize_sign(Xdb)

    out = []
    N = Xdb.shape[0]
    for qi, q in tqdm(enumerate(Xq)):
        sims = Xdb @ q
        # ground-truth Top-K (FP 기준)
        true_idx = np.argpartition(-sims, K-1)[:K]
        true_idx = true_idx[np.argsort(-sims[true_idx])]
        true_set = set(true_idx)

        # 해밍 계산
        bq = binarize_sign(q[None, :])[0]
        ham = (Bdb != bq).sum(axis=1)

        # 3) 해밍 오름차순, 동률 시 FP(sim) 내림차순으로 '후보 정렬'
        # np.lexsort는 마지막 key가 1순위이므로 (보조키=-sims, 주키=ham) 순서로 넣음
        order = np.lexsort(( -sims, ham ))  # ham ↑, tie에서 sims ↓

        # 4) 누적 스캔하며 true_set이 모두 포함되는 최초 위치 M 찾기
        seen = 0
        hit = set()
        M_min = None
        for rank_pos, idx in enumerate(order, start=1):  # 1-based 길이
            if idx in true_set and idx not in hit:
                hit.add(idx)
                seen += 1
                if seen == K:

                    M_min = rank_pos
                    break

        if M_min is None:
            # 이론상 M=N이면 항상 가능하지만, 안전망으로 처리
            M_min = N
        alpha_min = M_min / K

        out.append((qi, M_min, alpha_min))

    return pd.DataFrame(out, columns=["query_id", "M_min", "alpha_min"])


# =========================
# 5) 플롯: 곡선(중앙값+IQR) & 박스플롯(α별 분포)
#  (규칙: 한 그림에 하나의 플롯 유형만, seaborn 금지)
# =========================
def plot_recall_curve_median_iqr(df: pd.DataFrame, title: str, K: int):
    alphas = sorted(df["alpha"].unique())
    med = []; q25 = []; q75 = []
    for a in alphas:
        vals = df[df["alpha"]==a]["recall"].values
        med.append(np.median(vals))
        q25.append(np.quantile(vals, 0.25))
        q75.append(np.quantile(vals, 0.75))

    plt.figure()
    plt.plot(alphas, med, marker="o")
    plt.fill_between(alphas, q25, q75, alpha=0.3)
    plt.ylim(0, 1.01)
    plt.xlabel("alpha (oversampling factor)")
    plt.ylabel(f"Recall@{K}")
    plt.title(title + f" — median + IQR")
    plt.grid(True, linestyle="--", linewidth=0.5, alpha=0.6)
    plt.show()

def plot_recall_box_by_alpha(df: pd.DataFrame, title: str, K: int):
    alphas = sorted(df["alpha"].unique())
    data = [df[df["alpha"]==a]["recall"].values for a in alphas]

    plt.figure()
    plt.boxplot(data, labels=[str(a) for a in alphas], showfliers=False)
    plt.ylim(0, 1.01)
    plt.xlabel("alpha (oversampling factor)")
    plt.ylabel(f"Recall@{K} (per-query)")
    plt.title(title + " — per-alpha distribution")
    plt.grid(True, linestyle="--", linewidth=0.5, alpha=0.6)
    plt.show()

# =========================
# 6) 사용 예시: 데이터셋(모델)별 설정
#    - 각 항목: {"name": str, "path": str, "key_db": str, "key_q": str}
#    - key_* 는 HDF5 내 dataset 경로(혹은 group); 구조 모르면 먼저 load_hdf5_array(path, key=None)나 print(keys)
# =========================


# 1) alpha_min 분포: 박스플롯 (한 그림 = 한 유형)
def plot_alpha_min_box(df_min: pd.DataFrame, title: str):
    """
    df_min: columns = [query_id, M_min, alpha_min]
    """
    plt.figure()
    plt.boxplot(df_min["alpha_min"].values, labels=["alpha*"], showfliers=False)
    plt.xlabel("alpha* (per-query minimum)")
    plt.ylabel("alpha*")
    plt.title(title + " — alpha* distribution (boxplot)")
    plt.grid(True, linestyle="--", linewidth=0.5, alpha=0.6)
    plt.show()

# 2) alpha_min의 ECDF: α 증가에 따라 recall=1 달성 비율 (한 그림 = 선 그래프)
def plot_alpha_min_ecdf(df_min: pd.DataFrame, title: str):
    """
    S(a) = P(alpha_min <= a) 를 선 그래프로.
    """
    vals = np.sort(df_min["alpha_min"].values)
    y = np.arange(1, len(vals)+1) / len(vals)

    plt.figure()
    plt.plot(vals, y, marker="o")
    plt.xlabel("alpha")
    plt.ylabel("share of queries with recall@K = 1")
    plt.title(title + " — success-rate curve (ECDF of alpha*)")
    plt.grid(True, linestyle="--", linewidth=0.5, alpha=0.6)
    plt.ylim(0, 1.01)
    plt.show()

# 3) 기존 recall 곡선(중앙값+IQR)은 유지,
#    다만 '대표 alpha*' (예: median 또는 특정 분위수)를 선으로 덧그리기
def plot_recall_curve_with_alpha_star(
        df_recall: pd.DataFrame,  # columns = [query_id, alpha, recall]
        df_min: pd.DataFrame,     # columns = [query_id, M_min, alpha_min]
        title: str,
        K: int,
        alpha_star_quantile: float = 0.5,  # 0.5=median, 0.9=90%선 등
):
    # 기존 median+IQR 계산
    alphas = sorted(df_recall["alpha"].unique())
    med = []; q25 = []; q75 = []
    for a in alphas:
        vals = df_recall[df_recall["alpha"]==a]["recall"].values
        med.append(np.median(vals))
        q25.append(np.quantile(vals, 0.25))
        q75.append(np.quantile(vals, 0.75))

    # 대표 alpha* (예: median) 계산
    a_star = np.quantile(df_min["alpha_min"].values, alpha_star_quantile)

    plt.figure()
    plt.plot(alphas, med, marker="o")
    plt.fill_between(alphas, q25, q75, alpha=0.3)
    # 대표 alpha* 세로선(같은 '선' 유형)
    plt.axvline(a_star, linestyle="--", linewidth=1.2)
    plt.text(a_star, 0.02, f"alpha* q{int(alpha_star_quantile*100)}≈{a_star:.2f}",
             rotation=90, va="bottom", ha="right")

    plt.ylim(0, 1.01)
    plt.xlabel("alpha (oversampling factor)")
    plt.ylabel(f"Recall@{K}")
    plt.title(title + f" — median+IQR (vline at alpha* q{int(alpha_star_quantile*100)})")
    plt.grid(True, linestyle="--", linewidth=0.5, alpha=0.6)
    plt.show()

def l2_normalize(X: np.ndarray, eps: float = 1e-12) -> np.ndarray:
    X = X.astype(np.float32, copy=False)
    n = norm(X, axis=1, keepdims=True) + eps
    return X / n

DATASETS = [
    # 예시1) DBPedia BGE-384 (사용자 파일에 맞게 경로/키 수정)
    {
        "name": "dbpedia-qwen-4096",
        "path_db": "/home/jaewonoh/workspace/ann-benchmark/jaewon-test/dataset/dbpedia_qwen_4096_1m.fbin",
    },
    # {
    #     "name": "dbpedia-bge-768",
    #     "path_db": "dbpedia-bge-768-100k.hdf5",
    # },
]

print(DATASETS[0]['path_db'])

with open(DATASETS[0]['path_db'], "rb") as f:
    head = np.fromfile(f, dtype=np.int32, count=2)
print("header:", head)

X = read_fbin(DATASETS[0]['path_db'])
print(X.shape)
print("test")

import seaborn as sns


def plot_scatterplot(
        db_emb: np.ndarray,
        q_emb: np.ndarray,
        max_queries: Optional[int] = None,
        seed: int = 7,
) -> pd.DataFrame:
    """
    각 쿼리별로 recall@K = 1을 보장하는 최소 alpha(= M/K)를 계산하고,
    첫 번째 쿼리에 대한 sims와 ham의 산점도를 저장합니다.
    """
    rng = np.random.default_rng(seed)

    # 1) 정규화
    Xdb = l2_normalize(db_emb)
    Xq  = l2_normalize(q_emb)

    if max_queries is not None and Xq.shape[0] > max_queries:
        sel = rng.choice(Xq.shape[0], size=max_queries, replace=False)
        Xq = Xq[sel]

    # 2) BQ(sign)
    Bdb = binarize_sign(Xdb)

    # tqdm을 사용하여 진행 상황을 표시합니다.
    for qi, q in enumerate(tqdm(Xq, desc="Processing queries")):
        sims = Xdb @ q

        # 해밍 거리 계산
        bq = binarize_sign(q[None, :])[0]
        ham = (Bdb != bq).sum(axis=1)

        print(f"sims: {sims.shape}")
        print(f"ham: {ham.shape}")

        # --- 산점도 생성 및 저장 (첫 번째 쿼리에 대해서만) ---
        if qi == 0:
            plt.figure(figsize=(8, 6))
            sns.scatterplot(x = ham, y = sims, alpha=0.5, edgecolors='k', s=40)
            plt.title('Similarity vs. Hamming Distance (Query 0)')
            plt.xlabel('Hamming Distance')
            plt.ylabel('Cosine Similarity')
            plt.grid(True)

            # PNG 파일로 저장
            file_path = 'similarity_vs_hamming_distance.png'
            plt.savefig(file_path)
            print(f"산점도가 '{file_path}' 파일로 저장되었습니다.")
            # 첫 번째 쿼리에 대한 플롯만 생성하고 싶다면 아래 주석을 해제하세요.
            # break

        # (원래의 계산 로직은 여기에 계속됩니다)
        # ...

    # (결과를 DataFrame으로 반환하는 부분은 생략)
    return pd.DataFrame() # 임시 반환


# ALPHAS = [1, 1.5, 2, 3, 5, 10]
MAX_QUERIES = 100   # 쿼리 많으면 속도 위해 상한 (원하면 None)

for cfg in DATASETS:
    # 로드\

    X = read_fbin(cfg['path_db'])
    db = X[:-1000]
    q = X[-100:]


    # db = load_hdf5_array(cfg["path_db"], cfg["key_db"])
    # q  = load_hdf5_array(cfg["path_q"],  cfg["key_q"])
    # print(f"[{cfg['name']}] db={db.shape}, q={q.shape}")

    # 실험
    df = plot_scatterplot(db, q, max_queries=MAX_QUERIES)

# # =========================
# # 7) 실험 파라미터 설정
# # =========================
# K = 10
# ALPHAS = [1, 1.5, 2, 3, 5, 10]
# MAX_QUERIES = 100   # 쿼리 많으면 속도 위해 상한 (원하면 None)
#
# # =========================
# # 8) 실행
# # =========================
# all_results = []  # (dataset, query_id, alpha, recall)
#
# for cfg in DATASETS:
#     # 로드\
#
#     X = read_fbin(cfg['path_db'])
#     db = X[:-1000]
#     q = X[-100:]
#
#
#     # db = load_hdf5_array(cfg["path_db"], cfg["key_db"])
#     # q  = load_hdf5_array(cfg["path_q"],  cfg["key_q"])
#     # print(f"[{cfg['name']}] db={db.shape}, q={q.shape}")
#
#     # 실험
#     df = run_recall_curve_for_dataset(db, q, K=K, alphas=ALPHAS, max_queries=MAX_QUERIES)
#     df["dataset"] = cfg["name"]
#     all_results.append(df)
#
# # 합치기
# if len(all_results) == 0:
#     raise RuntimeError("DATASETS가 비어 있습니다. 경로/키를 올바르게 설정하세요.")
# res = pd.concat(all_results, ignore_index=True)
#
# def q(x, p): return np.quantile(x, p)
#
# summary = (
#     res.groupby(["dataset","alpha"])["recall"]
#     .agg(median="median", mean="mean",
#          p90=lambda x: q(x, 0.90),
#          p95=lambda x: q(x, 0.95),
#          p99=lambda x: q(x, 0.99))
#     .reset_index()
# )
#
# print(summary)
#
#
#
# # =========================
# # 7) 실험 파라미터 설정
# # =========================
# # K = 10
# Ks = [1, 3, 5, 10, 20]
# # ALPHAS = [1, 1.5, 2, 3, 5, 10]
# MAX_QUERIES = 200   # 쿼리 많으면 속도 위해 상한 (원하면 None)
#
# # =========================
# # 8) 실행
# # =========================
# # all_results = []  # (dataset, query_id, alpha, recall)
# for K in Ks:
#     for cfg in DATASETS:
#         # 로드
#
#         X = read_fbin(cfg['path_db'])
#         db = X[:-1000]
#         q = X[-100:]
#
#         # db = load_hdf5_array(cfg["path_db"], cfg["key_db"])
#         # q  = load_hdf5_array(cfg["path_q"],  cfg["key_q"])
#         # print(f"[{cfg['name']}] db={db.shape}, q={q.shape}")
#
#         # 2) 최소 alpha* 계산
#         df_min = min_alpha_for_recall1(db, q, K, max_queries=MAX_QUERIES)
#
#
#         # 필요하면 0.9 분위수도:
#         # plot_recall_curve_with_alpha_star(df_recall, df_min, "[MODEL/DATA]", K, alpha_star_quantile=0.9)
#         df_min["dataset"] = cfg["name"]
#         df_min["K"] = K
#         all_results.append(df_min)
#
# # 합치기
# if len(all_results) == 0:
#     raise RuntimeError("DATASETS가 비어 있습니다. 경로/키를 올바르게 설정하세요.")
# res_all = pd.concat(all_results, ignore_index=True)
# res_all['dataset_group'] = res_all['dataset'].str.split('-').str[1]
#
# df_alpha_min = res_all.groupby(["dataset", "K"])["alpha_min"].mean().reset_index()
# df_alpha_min['dim'] = df_alpha_min['dataset'].str.split('-').str[2].astype(int)
# df_alpha_min['dataset'] = df_alpha_min['dataset'].str.split('-').str[1]
# print(df_alpha_min[df_alpha_min['dataset'] == "qwen"].pivot(index=['dataset', 'K'], columns='dim', values='alpha_min'))
