<?php

return [
    'plugins' => [
        'EvaluationMethodTechnical' => ['namespace' => 'EvaluationMethodTechnical'],
        'EvaluationMethodSimple' => ['namespace' => 'EvaluationMethodSimple'],
        'EvaluationMethodDocumentary' => ['namespace' => 'EvaluationMethodDocumentary'],
        
        'MultipleLocalAuth' => [ 'namespace' => 'MultipleLocalAuth' ],
        'AldirBlanc' => [
            'namespace' => 'AldirBlanc',
            'config' => [
                'inciso1_enabled' => true,
                'inciso2_enabled' => true,
                'project_id' => 1,
                'inciso1_opportunity_id' => 3,
                'inciso2_opportunity_ids' => [
                    'São Paulo' => 33,
                    'Santo André' => 34,
                    'Ubatuba' => 35
                ]
            ],
        ],
    ]
];