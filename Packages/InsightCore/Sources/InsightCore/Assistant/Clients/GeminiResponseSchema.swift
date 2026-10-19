import Foundation

enum GeminiResponseSchema {
    /// Provider-specific wire schema. The domain answer remains InsightAnswer.
    static var responseSchema: [String: Any] { [
        "type": "OBJECT",
        "properties": [
            "status": ["type": "STRING", "enum": ["answered", "insufficient_data", "needs_clinician"]],
            "takeaway": ["type": "STRING"],
            "display_metrics": [
                "type": "ARRAY",
                "items": ["type": "STRING", "enum": MetricCatalog.enabled.map(\.rawValue)],
            ],
            "observations": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "text": ["type": "STRING"],
                        "metrics": [
                            "type": "ARRAY",
                            "items": ["type": "STRING", "enum": MetricCatalog.enabled.map(\.rawValue)],
                        ],
                    ],
                    "required": ["text", "metrics"],
                ],
            ],
            "general_info": ["type": "ARRAY", "items": ["type": "STRING"]],
            "limitations": ["type": "ARRAY", "items": ["type": "STRING"]],
        ],
        "required": ["status", "takeaway", "display_metrics", "observations", "general_info", "limitations"],
        "propertyOrdering": ["status", "takeaway", "display_metrics", "observations", "general_info", "limitations"],
    ] }
}
