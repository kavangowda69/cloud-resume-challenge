import unittest
from unittest.mock import patch, MagicMock
import visitor_counter

class TestVisitorCounter(unittest.TestCase):

    @patch('visitor_counter.boto3.resource')
    def test_lambda_handler(self, mock_boto3_resource):
        # Mock DynamoDB table and its return value
        mock_table = MagicMock()
        mock_boto3_resource.return_value.Table.return_value = mock_table

        # Fake return value when get_item is called
        mock_table.get_item.return_value = {'Item': {'id': 'visitor_count', 'count': 7}}
        
        # Simulate API Gateway event
        event = {}
        context = {}

        response = visitor_counter.lambda_handler(event, context)
        
        self.assertEqual(response['statusCode'], 200)
        self.assertIn('body', response)

if __name__ == '__main__':
    unittest.main()
