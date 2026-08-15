import cf from 'cloudfront';

const kvsId = 'fd3e0407-a074-47ff-99ea-1eb6ae9f6f1f'; 
const kvsHandle = cf.kvs();

async function handler(event) {
    const request = event.request;
    const cookies = request.cookies;
    
    let assignedVersion = '';
    let isNewAssignment = false;

    if (cookies['x-sp-ab'] && cookies['x-sp-ab'].value) {
        const cookieValue = cookies['x-sp-ab'].value;
        if (cookieValue === 'a' || cookieValue === 'b') {
            assignedVersion = cookieValue;
        }
    }

    if (!assignedVersion) {
        let weight = 0.5;
        
        try {
            const weightStr = await kvsHandle.get('weight');
            weight = parseFloat(weightStr);
        } catch (err) {
            console.log('KVS weight 읽기 실패, 기본값(0.5)을 사용합니다: ' + err);
        }

        if (Math.random() < weight) {
            assignedVersion = 'b';
        } else {
            assignedVersion = 'a';
        }
        isNewAssignment = true;
    }
        
    try {
        const kvsKey = 'version_' + assignedVersion;
        const newUri = await kvsHandle.get(kvsKey);
        
        if (newUri) {
            request.uri = newUri;
        }
    } catch (err) {
        console.log('KVS에서 URI 값을 가져오지 못했습니다: ' + err);
    }

    if (isNewAssignment) {
        request.headers['x-sp-ab-assigned'] = { value: assignedVersion };
    }

    return request;
}