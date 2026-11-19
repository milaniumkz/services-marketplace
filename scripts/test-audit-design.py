"""Regression for action-like div/span controls omitted by the earlier inventory."""
import importlib.util
import unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('audit',Path(__file__).with_name('audit-design.py'))
audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
class PrototypeControls(unittest.TestCase):
 def test_rendered_controls_keep_nested_text_and_action(self):
  parser=audit.Controls();parser.feed('<div class="render-input">Поиск <b>кампании</b></div><span class="render-button" data-action="save"><svg><path/></svg>Сохранить</span><span class="render-checkbox">Согласен</span><div class="render-select">Страна</div><a href="#home">Главная</a><div>Текст</div>')
  self.assertEqual(len(parser.controls),5)
  self.assertEqual([' '.join(c['label'].split()) for c in parser.controls],['Поиск кампании','Сохранить','Согласен','Страна','Главная'])
  self.assertEqual(parser.controls[1]['attributes']['data-action'],'save')
  self.assertEqual([c.get('prototype_control_type') for c in parser.controls[:4]],['input','button','checkbox','select'])
if __name__=='__main__':unittest.main()
