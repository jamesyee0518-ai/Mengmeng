import unittest
from unittest.mock import patch
import main as gateway

class ExpressionDeliveryTests(unittest.TestCase):
    def response(self, raw):
        return gateway.coerce_robot_response(gateway._extract_model_response(raw), {}, gateway.safe_robot_response())

    def test_structured_expression_reaches_animation(self):
        result = self.response('{"text":"我在呀，权哥。","expression":"caring"}')
        self.assertEqual(result['text'], '我在呀，权哥。')
        self.assertEqual(result['expression'], 'caring')
        self.assertEqual(result['mouth_action'], 'soft_smile')
        self.assertEqual(result['eye_action'], 'slow_blink')

    def test_legacy_stage_cues_are_removed_and_mapped(self):
        for raw in ['（羞涩微笑）我在呀。', '我在呀。（羞涩微笑）', '我在呀。**羞涩微笑**', '我在呀。 羞涩微笑', '【表情：羞涩微笑】我在呀。']:
            with self.subTest(raw=raw):
                result = self.response(raw)
                self.assertEqual(result['text'], '我在呀。')
                self.assertEqual(result['expression'], 'caring')
                self.assertTrue(result['model_repaired'])

    def test_multiline_dialogue_is_retained(self):
        result = self.response('(羞涩微笑)\n我在呀。\n想聊什么？')
        self.assertEqual(result['text'], '我在呀。\n想聊什么？')

    def test_explanations_and_non_stage_parentheses_are_not_removed(self):
        for text in ['“羞涩微笑”指的是害羞时的笑容。', '害羞，是一种常见的情绪。', '我推荐这本书（第二版）。', '微笑可以表达友好。']:
            self.assertEqual(self.response(text)['text'], text)

    def test_action_only_response_does_not_speak(self):
        result = self.response('（羞涩微笑）')
        self.assertEqual(result['text'], '')
        self.assertFalse(result['should_speak'])
        self.assertEqual(result['expression'], 'caring')

    def test_model_fields_survive_both_chat_and_vision(self):
        answer = {'choices': [{'message': {'content': '{"text":"我在。","expression":"happy"}'}}]}
        with patch.object(gateway.lmstudio_client, 'enabled', True), patch.object(gateway.lmstudio_client, '_post', return_value=answer):
            text = gateway.response_for_text('你好', settings={'allow_memory':False})
            vision = gateway.response_for_chat_vision('看一下', 'aGVsbG8=')
        for result in (text, vision):
            self.assertEqual(result['expression'], 'happy')
            self.assertEqual(result['text'], '我在。')
            self.assertEqual(result['mouth_action'], 'smile')

if __name__ == '__main__':
    unittest.main()
