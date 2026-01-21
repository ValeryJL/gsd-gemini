# gsd-gemini

Este repositorio alberga el proyecto GSD-Gemini, cuyo objetivo principal es utilizar Gemini CLI como un administrador de agentes inteligentes. En este enfoque, un **agente director** central será responsable de la gestión y orquestación de un conjunto de **agentes secundarios**.

El agente director recibirá un objetivo principal y, basándose en su entendimiento y análisis, delegará tareas específicas a los agentes secundarios más adecuados. Estos agentes secundarios, a su vez, ejecutarán sus tareas de forma autónoma. Si un agente secundario determina que una tarea es demasiado compleja o requiere conocimientos especializados adicionales, tendrá la capacidad de delegar sub-tareas a otros agentes (ya sean existentes o creados dinámicamente) para lograr su objetivo.

Este modelo jerárquico de delegación permitirá una gestión de cambios más eficiente y una resolución de problemas más robusta, aprovechando la capacidad de los agentes para colaborar y especializarse en diferentes aspectos de un objetivo.
