import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('lab',ROOT/'scripts/lab.py')
lab=importlib.util.module_from_spec(spec);spec.loader.exec_module(lab)

class LabTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.cfg=json.loads((ROOT/'lab.example.json').read_text())
        self.patcher=patch.object(lab,'ROOT',self.root);self.patcher.start();self.addCleanup(self.patcher.stop)
    def config(self):
        (self.root/'lab.local.json').write_text(json.dumps(self.cfg))
        return lab.config()
    def test_example(self):
        self.assertEqual(len(self.config()['nodes']['k8s']),3)
    def test_duplicate_ip_rejected(self):
        self.cfg['nodes']['ubuntu'][0]['ip']='192.168.56.10'
        with self.assertRaisesRegex(ValueError,'Duplicate'):self.config()
    def test_noncanonical_cidr_rejected(self):
        self.cfg['pod_cidr']='172.16.1.0/16'
        with self.assertRaises(ValueError):self.config()
    def test_overlapping_cidr_rejected(self):
        self.cfg['pod_cidr']='192.168.0.0/16'
        with self.assertRaisesRegex(ValueError,'overlap'):self.config()
    def test_existing_unowned_vm_not_modified(self):
        c=self.config();ovf=self.root/'test.ovf';ovf.touch()
        with patch.object(lab,'OVF',ovf),patch.object(lab,'ensure_network'),patch.object(lab,'vm_info',return_value={'VMState':'running'}),patch.object(lab,'output',return_value='No value set!'),patch.object(lab,'packer') as build,patch.object(lab,'start') as start:
            with self.assertRaisesRegex(ValueError,'not owned'):lab.up(c,'k8s')
            build.assert_not_called();start.assert_not_called()
    def test_order_and_join_token_sent_over_stdin(self):
        c=self.config();ovf=self.root/'test.ovf';ovf.touch();calls=[]
        def remote(cfg,node,command,**kwargs):
            calls.append((node['role'],command,kwargs))
            return subprocess.CompletedProcess([],0,stdout='kubeadm join 192.168.56.10:6443 --token test\n')
        with patch.object(lab,'OVF',ovf),patch.object(lab,'ensure_network'),patch.object(lab,'vm_info',return_value=None),patch.object(lab,'packer') as build,patch.object(lab,'start'),patch.object(lab,'ssh',side_effect=remote):
            lab.up(c,'k8s')
            self.assertEqual(build.call_count,3)
            self.assertIn('master.sh',calls[0][1])
            joins=[x for x in calls if 'node.sh' in x[1]]
            self.assertEqual(len(joins),2)
            self.assertTrue(all('input' in x[2] and '--token' not in x[1] for x in joins))

if __name__=='__main__':unittest.main()
