import http.client, json, os, sys, threading, time, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))
from server import State, serve

class ProtocolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = State('127.0.0.1',0)
        cls.server=serve(cls.s)
        cls.s.port=cls.server.server_address[1]
        cls.host=f'127.0.0.1:{cls.s.port}'
    @classmethod
    def tearDownClass(cls):
        cls.s.stop(); cls.server.shutdown(); cls.server.server_close()
    def req(self, method, path, body=None, headers=None):
        c=http.client.HTTPConnection('127.0.0.1',self.s.port,timeout=5)
        headers={'Host':self.host,**(headers or {})}
        c.request(method,path,body=body,headers=headers); r=c.getresponse(); data=r.read(); result=(r.status,dict(r.getheaders()),data);c.close();return result
    def test_a_unauthenticated_frame_denied(self):
        self.assertEqual(self.req('GET','/api/frame')[0],401)
    def test_b_origin_required(self):
        self.assertEqual(self.req('POST','/api/pair',json.dumps({'code':self.s.code}),{'Content-Type':'application/json'})[0],403)
    def test_c_wrong_code_denied(self):
        code='000000' if self.s.code!='000000' else '111111'
        self.assertEqual(self.req('POST','/api/pair',json.dumps({'code':code}),{'Content-Type':'application/json','Origin':'http://'+self.host})[0],401)
    def test_d_approval_and_revoke(self):
        def approve():
            req=self.s.requests.get(timeout=3); req['accepted']=True; req['event'].set()
        t=threading.Thread(target=approve);t.start()
        status,headers,_=self.req('POST','/api/pair',json.dumps({'code':self.s.code}),{'Content-Type':'application/json','Origin':'http://'+self.host})
        t.join();self.assertEqual(status,200);cookie=headers['Set-Cookie'].split(';')[0]
        self.assertTrue(json.loads(self.req('GET','/api/status',headers={'Cookie':cookie})[2])['connected'])
        self.assertEqual(self.req('POST','/api/disconnect',headers={'Cookie':cookie,'Origin':'http://'+self.host})[0],200)
        self.assertFalse(json.loads(self.req('GET','/api/status',headers={'Cookie':cookie})[2])['connected'])
    def test_e_host_header_rejected(self):
        self.assertEqual(self.req('GET','/',headers={'Host':'evil.example'})[0],403)
if __name__=='__main__':unittest.main()
