function handler(event) {
    const request = event.request;
    const response = event.response;
    
    const targetHeader = 'x-sp-ab-assigned';

    
    if (request.headers[targetHeader] && request.headers[targetHeader].value) {
        const assignedVersion = request.headers[targetHeader].value;
        if (!response.cookies) {
            response.cookies = {};
        }
        
        response.cookies['x-sp-ab'] = {
            value: assignedVersion,
            attributes: 'Path=/; Max-Age=86400'
        };
    }

    return response;
}
