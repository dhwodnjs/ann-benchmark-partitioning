import pgvector.psycopg
import psycopg
import time

from ..base.module import BaseANN

# TABLE = "items_glove_25_angular"
# TABLE = "items_gist_860_euclidean"
# TABLE = "items_gist_960_euclidean"
# TABLE = "dbpedia_openai_100k_angular"
# TABLE = "dbpedia_openai_1000k_angular"
# TABLE = "dbpedia_openai_1000k_angular_ivf"
# TABLE = "dbpedia_openai_1000k_angular_ivf_dstore"
# TABLE = "deep_10m_build_100_prt_64_pool_30_t3"
# TABLE = "deep_100k_build_100_prt_64_pool_30_v"
TABLE = "dbp_100k_build_90_prt_64_pool_30_t3"

class PGVector(BaseANN):
    def __init__(self, metric, method_param):
        self._metric = metric
        self._m = method_param['M']
        self._ef_construction = method_param['efConstruction']
        self._cur = None

        if TABLE.__contains__("hamming"):
            self._query = "SELECT id FROM " + TABLE + " ORDER BY embedding <~> binary_quantize(%s) LIMIT %s"
        else:
            if metric == "angular" or TABLE.endswith("angular"):
                self._query = "SELECT id FROM " + TABLE + " ORDER BY embedding <=> %s LIMIT %s"
            elif metric == "euclidean":
                self._query = "SELECT id FROM " + TABLE + " ORDER BY embedding <-> %s LIMIT %s"
            else:
                raise RuntimeError(f"unknown metric {metric}")

    def fit(self, X):
        print("TABLE: ", TABLE)
        # time.sleep(500)
        # print("awake")
        #subprocess.run("service postgresql start", shell=True, check=True, stdout=sys.stdout, stderr=sys.stderr)
        conn = psycopg.connect(host="localhost", user="ann", password="ann", dbname="ann", autocommit=True, port=8000)
        pgvector.psycopg.register_vector(conn)
        cur = conn.cursor()
        """
        # cur.execute("DROP TABLE IF EXISTS items")
        cur.execute("CREATE TABLE items (id int, embedding vector(%d))" % X.shape[1])
        cur.execute("ALTER TABLE items ALTER COLUMN embedding SET STORAGE PLAIN")
        print("copying data...")
        with cur.copy("COPY items (id, embedding) FROM STDIN WITH (FORMAT BINARY)") as copy:
            copy.set_types(["int4", "vector"])
            for i, embedding in enumerate(X):
                copy.write_row((i, embedding))

       
        print("creating index...")
        if self._metric == "angular":
            cur.execute(
                "CREATE INDEX ON items USING hnsw (embedding vector_cosine_ops) WITH (m = %d, ef_construction = %d)" % (self._m, self._ef_construction)
            )
        elif self._metric == "euclidean":
            cur.execute("CREATE INDEX ON items USING hnsw (embedding vector_l2_ops) WITH (m = %d, ef_construction = %d)" % (self._m, self._ef_construction))
        else:
            raise RuntimeError(f"unknown metric {self._metric}")
        print("done!")
        """
        print("skip insert and create")
        self._cur = cur

    def set_query_arguments(self, ef_search):
        self._ef_search = ef_search
        self._cur.execute("SET hnsw.ef_search = %d" % ef_search)
        self._cur.execute("SET enable_seqscan = OFF")
        self._cur.execute("SET ivfflat.probes = %d" % ef_search)

    def query(self, v, n):
        # print("query ", self._query)-
        # v_str = ','.join(map(str, v))
        # print(f"SELECT id FROM {TABLE} ORDER BY embedding <=> '[{v_str}]' LIMIT", n, ";");
        self._cur.execute(self._query, (v, n), binary=True, prepare=True)
        return [id for id, in self._cur.fetchall()]

    def get_memory_usage(self):
        if self._cur is None:
            return 0
        # self._cur.execute("SELECT pg_relation_size('items_embedding_idx')")
        return 0
        # return self._cur.fetchone()[0] / 1024

    def __str__(self):
        return f"PGVector(m={self._m}, ef_construction={self._ef_construction}, ef_search={self._ef_search})"
