"""Cliente HTTP com ritmo, tratamento de 429 e cache em disco.

- No máximo 1 pedido por segundo (``min_interval``), inclusive nas repetições.
- 429: espera o ``Retry-After`` (com teto) e tenta de novo.
- Cache: um arquivo JSON por URL, num diretório fora do git e separado dos scripts.
  O conteúdo baixado é só dado: é lido como JSON e nunca executado.
- ``sanitize`` roda antes de gravar no cache, então campos de resposta nem chegam ao disco.
"""

import hashlib
import json
import os
import time
import urllib.error
import urllib.request

USER_AGENT = "IaGo-acervo/1.0"
MAX_BYTES = 20 * 1024 * 1024


class FetchError(RuntimeError):
    pass


class _PrefixRedirect(urllib.request.HTTPRedirectHandler):
    """Recusa redirecionamento para fora do prefixo autorizado da fonte."""

    def __init__(self, prefixes):
        self.prefixes = tuple(prefixes)

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.startswith(self.prefixes):
            raise FetchError(f"redirecionamento recusado (fora da fonte autorizada): {newurl}")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class Fetcher:
    def __init__(
        self,
        cache_dir,
        allowed_prefixes,
        sanitize=lambda url, data: data,
        min_interval=1.1,
        max_attempts=6,
        max_wait=120.0,
        offline=False,
        opener=None,
        sleep=time.sleep,
        clock=time.monotonic,
    ):
        self.cache_dir = cache_dir
        self.allowed_prefixes = tuple(allowed_prefixes)
        self.sanitize = sanitize
        self.min_interval = min_interval
        self.max_attempts = max_attempts
        self.max_wait = max_wait
        self.offline = offline
        if opener is None:
            built = urllib.request.build_opener(_PrefixRedirect(self.allowed_prefixes))
            opener = lambda req: built.open(req, timeout=30)  # noqa: E731
        self._open = opener
        self._sleep = sleep
        self._clock = clock
        self._last = None
        self.network_requests = 0
        self.cache_hits = 0
        os.makedirs(cache_dir, exist_ok=True)

    def _path(self, url):
        name = hashlib.sha256(url.encode()).hexdigest()[:40] + ".json"
        return os.path.join(self.cache_dir, name)

    def _throttle(self):
        if self._last is not None:
            wait = self.min_interval - (self._clock() - self._last)
            if wait > 0:
                self._sleep(wait)
        self._last = self._clock()

    def get_json(self, url):
        if not url.startswith(self.allowed_prefixes):
            raise FetchError(f"URL fora da fonte autorizada: {url}")
        path = self._path(url)
        corrupt = False
        if os.path.exists(path):
            try:
                with open(path, encoding="utf-8") as f:
                    cached = json.load(f)
                if cached.get("url") == url:
                    data = cached["data"]
                    self.cache_hits += 1
                    return data
            except (ValueError, OSError, KeyError, AttributeError, TypeError):
                corrupt = True  # arquivo truncado ou ilegível: vale como cache ausente
        if self.offline:
            motivo = "cache corrompido" if corrupt else "sem cache"
            raise FetchError(
                f"{motivo} para {url} (modo --offline); apague {path} e rode sem --offline"
            )
        data = self.sanitize(url, self._download(url))
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"url": url, "data": data}, f, ensure_ascii=False)
        os.replace(tmp, path)
        return data

    def _download(self, url):
        backoff = 2.0
        for attempt in range(1, self.max_attempts + 1):
            self._throttle()
            self.network_requests += 1
            req = urllib.request.Request(
                url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"}
            )
            try:
                with self._open(req) as resp:
                    final = getattr(resp, "geturl", lambda: url)()
                    if not final.startswith(self.allowed_prefixes):
                        raise FetchError(f"redirecionado para fora da fonte autorizada: {final}")
                    body = resp.read(MAX_BYTES + 1)
                if len(body) > MAX_BYTES:
                    raise FetchError(f"resposta grande demais: {url}")
                return json.loads(body.decode("utf-8"))
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    retry_after = e.headers.get("Retry-After") if e.headers else None
                    try:
                        wait = float(retry_after)
                    except (TypeError, ValueError):
                        wait = 10.0 * attempt
                    self._sleep(min(max(wait, self.min_interval), self.max_wait))
                elif 500 <= e.code < 600:
                    self._sleep(backoff)
                    backoff *= 2
                else:
                    raise FetchError(f"HTTP {e.code} em {url}") from e
            except (urllib.error.URLError, TimeoutError, ConnectionError, json.JSONDecodeError):
                self._sleep(backoff)
                backoff *= 2
        raise FetchError(f"falhou após {self.max_attempts} tentativas: {url}")
