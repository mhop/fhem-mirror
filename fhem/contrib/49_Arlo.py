import base64
import sys
import time
import cloudscraper
import email
import imaplib
import re

class Arlo:
    def __init__(self, tfa_mail_check) -> None:
        self._tfa_mail_check = tfa_mail_check
        browser = {
            'browser': 'chrome',
            'platform': 'linux',
            'mobile': False
        }
        self._session = cloudscraper.create_scraper(browser=browser)
        self._headers = {
            "Accept": "application/json, text/plain, */*",
            "Referer": "https://my.arlo.com",
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.96 Safari/537.36",
            "Source": "arloCamWeb"
        }
        self._baseUrl = "https://ocapi-app.arlo.com/api/"
        self._token = None

    def login(self, username, password):
        status("login")
        json = {"email": username, "password": encode(password), "language": "en", "EnvSource": "prod"}
        attempt = 0
        while attempt < 3:
            attempt += 1
            try:
                r = self._session.post(self._baseUrl + "auth", json=json, headers=self._headers)
                if r.status_code == 200:
                    data = _get_data(r)
                    if data is not None:
                        self._request_factors(data)
                    return
                if r.status_code == 400:
                    error("Bad auth request - probably the credentials are wrong.")
                    return
            except Exception as e:
                log(e)
            time.sleep(3)
        status("loginFailed")

    def _request_factors(self, data):
        status("getFactors")
        self._token = data["token"]
        self._headers["Authorization"] = encode(self._token)
        r = self._session.get(self._baseUrl + "getFactors?data=" + str(data["authenticated"]), headers=self._headers)
        data = _get_data(r)
        if data is None:
            error("getFactors not successful, response code " + str(r.status_code))
            return

        factor_id = None
        for factor in data["items"]:
            if factor["factorType"] == "EMAIL":
                self._auth_tfa(factor["factorId"])
                return
        error("email factor not found.")

    def _auth_tfa(self, factor_id):
        status("startAuth")
        self._tfa_mail_check.open()

        json = {"factorId": factor_id}
        r = self._session.post(self._baseUrl + "startAuth", json=json, headers=self._headers)
        data = _get_data(r)
        if data is None:
            error("startAuth not successful, response code " + str(r.status_code))
            return
        factor_auth_code = data["factorAuthCode"]

        status("waitFor2FA")
        code = self._tfa_mail_check.get()
        self._tfa_mail_check.close()
        log("Try to login with code " + code)

        status("finishAuth")
        json = {"factorAuthCode": factor_auth_code, "otp": code}
        r = self._session.post(self._baseUrl + "finishAuth", json=json, headers=self._headers)
        data = _get_data(r)
        if data is None:
            error("finishAuth not successful, response code " + str(r.status_code))
            return

        self._token = data["token"]
        self._headers["Authorization"] = encode(self._token)
        r = self._session.get(self._baseUrl + "validateAccessToken?data=" + str(data["authenticated"]),
                              headers=self._headers)
        if r.status_code != 200:
            error("validateAccessToken not successful, response code " + str(r.status_code))
            return

        print("cookies:", self._get_cookie_header())
        print("token:", self._token)
        print("userId:", data["userId"])
        print("end")

    def _get_cookie_header(self):
        cookie_header = ""
        for cookie in self._session.cookies:
            if cookie_header != "":
                cookie_header += "; "
            cookie_header += cookie.name + "=" + cookie.value
        return cookie_header


def _get_data(r):
    if r.status_code != 200:
        return None
    try:
        body = r.json()
    except Exception as e:
        log(r.content)
        error(e)
        return None

    if "meta" in body:
        if body["meta"]["code"] == 200:
            return body["data"]
    elif "success" in body:
        if body["success"]:
            if "data" in body:
                return body["data"]
    log(r.json())
    return None


class TfaMailCheck:
    def __init__(self, mail_server, username, password) -> None:
        self._imap = None
        self._mail_server = mail_server
        self._username = username
        self._password = password

    def open(self):
        self._imap = imaplib.IMAP4_SSL(self._mail_server)
        res, status = self._imap.login(self._username, self._password)
        if res.lower() != "ok":
            return False
        res, status = self._imap.select()
        if res.lower() != "ok":
            return False
        res, ids = self._imap.search(None, "FROM", "do_not_reply@arlo.com")
        for msg_id in ids[0].split():
            self._determine_code_and_delete_mail(msg_id)
        if res.lower() != "ok":
            return False

    def get(self):
        timeout = time.time() + 100
        while True:
            time.sleep(5)
            if time.time() > timeout:
                return None

            try:
                self._imap.check()
                res, ids = self._imap.search(None, "FROM", "do_not_reply@arlo.com")
                for msg_id in ids[0].split():
                    code = self._determine_code_and_delete_mail(msg_id)
                    if code is not None:
                        return code

            except Exception as e:
                return None

    def _determine_code_and_delete_mail(self, msg_id):
        res, msg = self._imap.fetch(msg_id, "(RFC822)")
        for part in email.message_from_bytes(msg[0][1]).walk():
            if part.get_content_type() == "text/html":
                for line in part.get_payload().splitlines():
                    code = re.match(r"^\W*(\d{6})\W*$", line)
                    if code is not None:
                        self._imap.store(msg_id, "+FLAGS", "\\Deleted")
                        return code.group(1)

    def close(self):
        self._imap.close()
        self._imap.logout()


def status(status):
    print("status:", status, flush=True)

def log(msg):
    print("log:", msg, flush=True)

def error(msg):
    print("error:", msg, flush=True)

def encode(s):
    return base64.b64encode(s.encode()).decode()


if __name__ == '__main__':
    if len(sys.argv) < 6:
        error("5 arguments expected: arlo user, arlo password, imap server, email user, email password")
    tfa_mail_check = TfaMailCheck(sys.argv[3], sys.argv[4], sys.argv[5])
    arlo = Arlo(tfa_mail_check)
    arlo.login(sys.argv[1], sys.argv[2])
